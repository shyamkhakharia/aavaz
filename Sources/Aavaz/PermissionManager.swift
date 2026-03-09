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
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// Resets the TCC entry for this app by removing and re-adding.
    /// Useful after rebuilds that change the ad-hoc code signature.
    func resetAndPromptAccessibility() {
        // Remove stale entry via tccutil (resets for our bundle ID)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        task.arguments = ["reset", "Accessibility", Bundle.main.bundleIdentifier ?? "com.aavaz.app"]
        try? task.run()
        task.waitUntilExit()

        // Now re-prompt so macOS registers the new binary
        promptAccessibility()
    }
}
