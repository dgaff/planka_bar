import Foundation
import Combine

/// Non-secret settings persisted in UserDefaults (secrets live in Keychain),
/// plus a cache of the last-fetched Planka structure so the card popup opens
/// instantly even before a network refresh completes.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private let defaults = UserDefaults.standard

    @Published var serverURL: String { didSet { defaults.set(serverURL, forKey: "serverURL") } }
    @Published var defaultProjectId: String { didSet { defaults.set(defaultProjectId, forKey: "defaultProjectId") } }
    @Published var defaultBoardId: String { didSet { defaults.set(defaultBoardId, forKey: "defaultBoardId") } }
    @Published var defaultListId: String { didSet { defaults.set(defaultListId, forKey: "defaultListId") } }
    /// Empty string means "None".
    @Published var defaultLabelId: String { didSet { defaults.set(defaultLabelId, forKey: "defaultLabelId") } }

    /// Where new cards are inserted in the list. Default: top.
    @Published var newCardsAtTop: Bool { didSet { defaults.set(newCardsAtTop, forKey: "newCardsAtTop") } }

    @Published var hotkeyKeyCode: Int { didSet { defaults.set(hotkeyKeyCode, forKey: "hotkeyKeyCode") } }
    @Published var hotkeyModifiers: Int { didSet { defaults.set(hotkeyModifiers, forKey: "hotkeyModifiers") } }

    private init() {
        serverURL = defaults.string(forKey: "serverURL") ?? ""
        defaultProjectId = defaults.string(forKey: "defaultProjectId") ?? ""
        defaultBoardId = defaults.string(forKey: "defaultBoardId") ?? ""
        defaultListId = defaults.string(forKey: "defaultListId") ?? ""
        defaultLabelId = defaults.string(forKey: "defaultLabelId") ?? ""
        newCardsAtTop = defaults.object(forKey: "newCardsAtTop") as? Bool ?? true
        // Default shortcut: ⌃⌥N (keyCode 45 = "N"; carbon controlKey|optionKey)
        hotkeyKeyCode = defaults.object(forKey: "hotkeyKeyCode") as? Int ?? 45
        hotkeyModifiers = defaults.object(forKey: "hotkeyModifiers") as? Int ?? (4096 + 2048)
    }

    // MARK: - Cached Planka structure (for instant popup)

    struct CachedStructure: Codable {
        var projects: [PlankaProject]
        var boards: [PlankaBoard]
        var listsByBoard: [String: [PlankaList]]
        var labelsByBoard: [String: [PlankaLabel]]
    }

    var cachedStructure: CachedStructure? {
        get {
            guard let data = defaults.data(forKey: "cachedStructure") else { return nil }
            return try? JSONDecoder().decode(CachedStructure.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: "cachedStructure")
            } else {
                defaults.removeObject(forKey: "cachedStructure")
            }
        }
    }

    func mergeBoardDetails(boardId: String, lists: [PlankaList], labels: [PlankaLabel]) {
        var cache = cachedStructure ?? CachedStructure(projects: [], boards: [], listsByBoard: [:], labelsByBoard: [:])
        cache.listsByBoard[boardId] = lists
        cache.labelsByBoard[boardId] = labels
        cachedStructure = cache
    }

    func replaceProjectsAndBoards(projects: [PlankaProject], boards: [PlankaBoard]) {
        var cache = cachedStructure ?? CachedStructure(projects: [], boards: [], listsByBoard: [:], labelsByBoard: [:])
        cache.projects = projects
        cache.boards = boards
        cachedStructure = cache
    }

    func clearAll() {
        cachedStructure = nil
        defaultProjectId = ""
        defaultBoardId = ""
        defaultListId = ""
        defaultLabelId = ""
    }
}
