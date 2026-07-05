import AppKit

// Entry point. We use an explicit NSApplication + AppDelegate (rather than the
// SwiftUI App lifecycle) because a menu bar utility needs precise control over
// activation, panels, and the status item.
@main
enum PlankaBarMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // no Dock icon; LSUIElement also set in Info.plist
        app.run()
    }
}
