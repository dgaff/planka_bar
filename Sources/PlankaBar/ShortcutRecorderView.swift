import SwiftUI
import AppKit
import Carbon.HIToolbox

/// Click-to-record shortcut field. While recording, the next key press with
/// at least one modifier becomes the new global shortcut. Esc cancels.
struct ShortcutRecorderView: NSViewRepresentable {
    @Binding var keyCode: Int
    @Binding var modifiers: Int
    var onChange: () -> Void

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.onCapture = { code, mods in
            keyCode = Int(code)
            modifiers = Int(mods)
            onChange()
        }
        return button
    }

    func updateNSView(_ nsView: RecorderButton, context: Context) {
        nsView.currentDisplay = KeyCombo.display(keyCode: UInt32(keyCode), carbonModifiers: UInt32(modifiers))
        nsView.refreshTitle()
    }
}

final class RecorderButton: NSButton {
    var onCapture: ((UInt32, UInt32) -> Void)?
    var currentDisplay: String = ""
    private var recording = false

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(toggleRecording)
        refreshTitle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func refreshTitle() {
        title = recording ? "Type shortcut… (⎋ to cancel)" : currentDisplay
    }

    @objc private func toggleRecording() {
        recording.toggle()
        refreshTitle()
        if recording {
            window?.makeFirstResponder(self)
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func resignFirstResponder() -> Bool {
        recording = false
        refreshTitle()
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard recording else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == UInt16(kVK_Escape) {
            recording = false
            refreshTitle()
            return
        }
        let mods = KeyCombo.carbonModifiers(from: event.modifierFlags)
        // Require at least one non-shift modifier so plain typing can't become a global hotkey.
        guard mods != 0, mods != UInt32(shiftKey) else {
            NSSound.beep()
            return
        }
        recording = false
        onCapture?(UInt32(event.keyCode), mods)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if recording {
            keyDown(with: event)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
