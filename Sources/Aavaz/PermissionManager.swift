import AVFoundation
import AppKit

@MainActor
final class PermissionManager {
    /// Track whether we've already shown the accessibility alert this session.
    private var hasShownAccessibilityAlert = false

    func isMicrophoneAuthorized() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    func isMicrophoneUndetermined() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined
    }

    func isAccessibilityTrusted() -> Bool {
        // Check WITHOUT prompting (prompt: false)
        AXIsProcessTrustedWithOptions(
            ["AXTrustedCheckOptionPrompt" as CFString: false] as CFDictionary
        )
    }

    func requestMicrophoneIfNeeded() async {
        guard isMicrophoneUndetermined() else { return }
        _ = await AudioRecorder.requestMicrophoneAccess()
    }

    func promptAccessibilityIfNeeded() {
        guard !isAccessibilityTrusted(), !hasShownAccessibilityAlert else { return }
        hasShownAccessibilityAlert = true

        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "Aavaz needs Accessibility permission to type transcribed text at your cursor.\n\nGrant access in System Settings → Privacy & Security → Accessibility."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }
}
