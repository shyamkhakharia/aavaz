import AVFoundation
import AppKit

@MainActor
final class PermissionManager {
    /// Key for persisting whether we've shown the accessibility alert.
    private static let accessibilityAlertShownKey = "accessibilityAlertShown"

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
        guard !isAccessibilityTrusted() else { return }
        guard !UserDefaults.standard.bool(forKey: Self.accessibilityAlertShownKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.accessibilityAlertShownKey)
        promptAccessibility()
    }

    /// Prompts for accessibility — triggers macOS system dialog which registers the app in the list.
    func promptAccessibility() {
        // This call with prompt:true is what actually adds the app to the Accessibility list
        let trusted = AXIsProcessTrustedWithOptions(
            ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary
        )
        if !trusted {
            // Also open System Settings so user can toggle it on
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }
}
