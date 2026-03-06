import AVFoundation
import AppKit

@MainActor
final class PermissionManager {
    func checkMicrophonePermission() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    func checkAccessibilityPermission() -> Bool {
        AXIsProcessTrustedWithOptions(
            ["AXTrustedCheckOptionPrompt" as CFString: false] as CFDictionary
        )
    }

    func requestMicrophonePermission() async -> Bool {
        await AudioRecorder.requestMicrophoneAccess()
    }

    func promptAccessibilityPermission() {
        let trusted = AXIsProcessTrustedWithOptions(
            ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary
        )
        if !trusted {
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = "Aavaz needs Accessibility permission to inject text at your cursor. Please grant access in System Settings → Privacy & Security → Accessibility."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Later")

            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
        }
    }

    func ensurePermissions() async -> Bool {
        let micGranted = await requestMicrophonePermission()
        if !micGranted {
            let alert = NSAlert()
            alert.messageText = "Microphone Permission Required"
            alert.informativeText = "Aavaz needs microphone access to record your voice."
            alert.alertStyle = .critical
            alert.runModal()
            return false
        }

        if !checkAccessibilityPermission() {
            promptAccessibilityPermission()
        }

        return true
    }
}
