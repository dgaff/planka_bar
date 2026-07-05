# PlankaBar — Mac menu bar app for quick Planka card capture

Companion utility for Planka (kanban): lives in the menu bar, global hotkey pops
up a "new card" panel, Enter sends the card. See `prd.md` for the original spec.

## Decisions made with Doug (2026-07-05)

- **Stack:** native Swift + SwiftUI, built as a Swift Package executable (no
  Xcode project). `scripts/build_app.sh` assembles and ad-hoc signs
  `build/PlankaBar.app`.
- **PRD's "Category" = Planka Label.** Since cards must be created inside a
  List (board column), Settings and the popup also expose a List picker.
- **Planka version:** 2.x API (`type: "project"` on card creation, `card-labels`
  endpoint), with fallbacks for 1.x (drop `type` on 400/422, `labels` endpoint
  on 404).
- **Auth:** username/password → `POST /api/access-tokens`, Bearer token.
  Token AND credentials stored in Keychain (service `com.douggaff.plankabar`);
  credentials enable silent re-login on 401. No browser/SSO flow.
- **Hotkey:** Carbon `RegisterEventHotKey` — deliberately chosen because it
  requires **no** Accessibility/Input Monitoring permission. Default: ⌃⌥N.
- **Launch at login:** `SMAppService.mainApp` (macOS 13+ min target). Works
  reliably only when the app is in a stable path (e.g. /Applications).
- **Notifications:** custom auto-dismissing HUD (`Toast.swift`) instead of
  UNUserNotificationCenter — no permission prompt needed.
- **"Self-signed":** ad-hoc codesign (`codesign --sign -`) in the build script.

## Architecture (Sources/PlankaBar/)

- `Main.swift` — @main, NSApplication + AppDelegate, `.accessory` policy.
  AppDelegate installs a hidden main menu with standard Edit actions — without
  it, ⌘V/⌘C/⌘A/⌘Z don't reach any text field (paste-into-password bug, fixed
  2026-07-05).
- `AppDelegate.swift` — status item + menu (Create New Card / Settings… / Quit),
  owns the Settings window and the floating New Card NSPanel (Spotlight-ish,
  positioned above center). First run with empty server URL auto-opens Settings.
- `PlankaClient.swift` — async REST client; 401 → one silent re-login + retry.
- `PlankaModels.swift` — Codable models; Planka ids are JSON strings.
- `PlankaData.swift` — @MainActor ObservableObject; shared snapshot of
  projects/boards/lists/labels, seeded from UserDefaults cache
  (`SettingsStore.cachedStructure`) so the popup opens instantly offline-ish,
  refreshed in background.
- `SettingsStore.swift` — UserDefaults-backed settings (URL, default
  project/board/list/label ids, hotkey keyCode+carbonModifiers) + structure cache.
- `Keychain.swift` — token/username/password.
- `HotKeyManager.swift` + `ShortcutRecorderView.swift` — Carbon hotkey +
  click-to-record UI (requires ≥1 non-shift modifier).
- `SettingsView.swift` / `NewCardView.swift` — SwiftUI forms.
- `Toast.swift` — success/warning HUD panel.
- `StatusIcon.swift` — programmatic template icon (kanban columns, Planka-style).

Popup seeding: `LastUsedSelection` (in `NewCardView.swift`) remembers the
project/board/list/label of the last successfully created card and seeds the
next popup — Settings defaults are not modified and win again after relaunch
(Doug's burst-entry use case, 2026-07-05).

Card placement: controlled by the `newCardsAtTop` setting (default true).
Before creating, fetches the board's cards for the target list and posts
`position: min/2` (top) or `max + 65536` (bottom). Verified live: Planka
sorts by position, so min/2 lands first in the list.

## Build / run

```sh
scripts/build_app.sh            # → build/PlankaBar.app (release, ad-hoc signed)
open build/PlankaBar.app
```

Swift language mode 5 (tools-version 5.9) to avoid Swift 6 strict-concurrency
churn; key classes are @MainActor where needed.

## Status / TODO

- [X] Builds clean, launches, menu + first-run Settings verified running.
- [X] **API contract verified against Doug's dev Planka 2.x** at
  `http://localhost:3000` (2026-07-05, admin `REDACTED` / REDACTED):
  login `{item: <jwt>}`, GET /api/projects → `included.boards`, GET
  /api/boards/:id → `included.{lists,labels,cards}` with list types
  active/archive/trash, POST /api/lists/:id/cards with `type:"project"` → 200,
  POST /api/cards/:id/card-labels `{labelId}` → 200. All matched the client
  code exactly — no changes needed. (1.x fallbacks kept but unexercised.)
- [X] Verify hotkey capture UX and launch-at-login from /Applications.
- [ ] Possible nice-to-haves discussed: description field on the popup,
  Esc-to-dismiss (done via cancelAction), better Planka-logo-accurate icon.
