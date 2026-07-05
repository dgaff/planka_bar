import AppKit
import SwiftUI

/// Small self-dismissing HUD ("Card added ✓") shown near the top of the screen.
/// Used instead of UNUserNotificationCenter so no notification permission is needed.
enum Toast {
    private static var window: NSPanel?

    @MainActor
    static func show(_ message: String, systemImage: String = "checkmark.circle.fill") {
        window?.orderOut(nil)

        let content = HStack(spacing: 8) {
            Image(systemName: systemImage).foregroundStyle(.green)
            Text(message).font(.system(size: 14, weight: .medium))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)

        let hosting = NSHostingView(rootView: content)
        hosting.frame.size = hosting.fittingSize

        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: hosting.fittingSize))
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        effect.addSubview(hosting)
        panel.contentView = effect

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let origin = NSPoint(x: frame.midX - hosting.fittingSize.width / 2,
                                 y: frame.maxY - hosting.fittingSize.height - 12)
            panel.setFrameOrigin(origin)
        }
        panel.orderFrontRegardless()
        window = panel

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            guard window === panel else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.35
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.orderOut(nil)
                if window === panel { window = nil }
            })
        }
    }
}
