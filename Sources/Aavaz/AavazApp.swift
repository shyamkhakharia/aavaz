import AppKit

@MainActor
final class AavazApp: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let audioRecorder = AudioRecorder()
    private let transcriber = WhisperTranscriber()
    private let textInjector = TextInjector()
    private let hotkeyMonitor = HotkeyMonitor()
    private let modelManager = ModelManager()
    private let prefsManager = PreferencesManager()
    private let permissionManager = PermissionManager()

    private var preferences: Preferences = .default
    private var isRecording = false
    private var isTranscribing = false

    // Menu items that need updating
    private var statusMenuItem: NSMenuItem?
    private var profileMenuItems: [NSMenuItem] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        preferences = prefsManager.load()
        setupMenuBar()
        configureFromPreferences()

        Task {
            let granted = await permissionManager.ensurePermissions()
            if granted {
                hotkeyMonitor.start()
            }
        }
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateStatusIcon(recording: false)

        let menu = NSMenu()

        // Status
        let status = NSMenuItem(title: "Ready", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        statusMenuItem = status

        menu.addItem(.separator())

        // Profile picker
        let profileHeader = NSMenuItem(title: "Profile", action: nil, keyEquivalent: "")
        profileHeader.isEnabled = false
        menu.addItem(profileHeader)

        for (index, profile) in preferences.profiles.enumerated() {
            let item = NSMenuItem(
                title: "  \(profile.name) (\(profile.modelName))",
                action: #selector(selectProfile(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = index
            item.state = index == preferences.activeProfileIndex ? .on : .off
            menu.addItem(item)
            profileMenuItems.append(item)
        }

        menu.addItem(.separator())

        // Download model
        let download = NSMenuItem(title: "Download Current Model…", action: #selector(downloadCurrentModel), keyEquivalent: "d")
        download.target = self
        menu.addItem(download)

        menu.addItem(.separator())

        // Quit
        let quit = NSMenuItem(title: "Quit Aavaz", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem?.menu = menu
    }

    private func updateStatusIcon(recording: Bool) {
        guard let button = statusItem?.button else { return }
        let symbolName = recording ? "mic.fill" : "mic"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Aavaz")
        image?.isTemplate = !recording
        if recording {
            button.contentTintColor = .systemRed
        } else {
            button.contentTintColor = nil
        }
        button.image = image
    }

    private func updateStatus(_ text: String) {
        statusMenuItem?.title = text
    }

    private func configureFromPreferences() {
        hotkeyMonitor.triggerKeyCode = preferences.triggerKeyCode
        hotkeyMonitor.doubleTapWindow = preferences.doubleTapWindow
        textInjector.injectionDelay = preferences.activeProfile.injectionDelay
        textInjector.restoreClipboard = preferences.restoreClipboard

        hotkeyMonitor.onDoubleTap = { [weak self] in
            self?.toggleRecording()
        }
        hotkeyMonitor.onCancel = { [weak self] in
            self?.cancelRecording()
        }
    }

    @objc private func selectProfile(_ sender: NSMenuItem) {
        let index = sender.tag
        guard index >= 0, index < preferences.profiles.count else { return }

        preferences.activeProfileIndex = index
        try? prefsManager.save(preferences)

        for (i, item) in profileMenuItems.enumerated() {
            item.state = i == index ? .on : .off
        }

        textInjector.injectionDelay = preferences.activeProfile.injectionDelay
        updateStatus("Profile: \(preferences.activeProfile.name)")
    }

    @objc private func downloadCurrentModel() {
        let profile = preferences.activeProfile
        guard let modelName = ModelManager.ModelName(rawValue: profile.modelName) else { return }

        if modelManager.isModelDownloaded(modelName) {
            updateStatus("Model already downloaded")
            return
        }

        updateStatus("Downloading \(profile.modelName)…")

        Task {
            do {
                try await modelManager.downloadModel(modelName) { [weak self] progress in
                    DispatchQueue.main.async {
                        self?.updateStatus("Downloading… \(Int(progress * 100))%")
                    }
                }
                updateStatus("Download complete")
            } catch {
                updateStatus("Download failed: \(error.localizedDescription)")
            }
        }
    }

    private func toggleRecording() {
        if isRecording {
            stopRecordingAndTranscribe()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        guard !isRecording, !isTranscribing else { return }

        // Check model is available
        let profile = preferences.activeProfile
        guard let modelName = ModelManager.ModelName(rawValue: profile.modelName) else { return }

        if !modelManager.isModelDownloaded(modelName) {
            updateStatus("Model not downloaded")
            playSound("Basso")
            return
        }

        do {
            try audioRecorder.startRecording()
            isRecording = true
            updateStatusIcon(recording: true)
            updateStatus("Recording…")
            playSound("Tink")
        } catch {
            updateStatus("Recording failed: \(error.localizedDescription)")
            playSound("Basso")
        }
    }

    private func stopRecordingAndTranscribe() {
        guard isRecording else { return }

        let audioBuffer = audioRecorder.stopRecording()
        isRecording = false
        updateStatusIcon(recording: false)
        playSound("Pop")

        guard !audioBuffer.isEmpty else {
            updateStatus("No audio recorded")
            return
        }

        isTranscribing = true
        updateStatus("Transcribing…")

        let profile = preferences.activeProfile
        let modelPath = modelManager.modelPath(
            for: ModelManager.ModelName(rawValue: profile.modelName)!
        ).path

        Task.detached { [weak self] in
            guard let self else { return }

            let config = WhisperTranscriber.TranscriptionConfig(
                modelPath: modelPath,
                useVAD: profile.useVAD,
                initialPrompt: profile.initialPrompt.isEmpty ? nil : profile.initialPrompt,
                useCoreML: profile.useCoreML
            )

            do {
                let text = try self.transcriber.transcribe(audioBuffer: audioBuffer, config: config)

                await MainActor.run {
                    self.isTranscribing = false
                    if text.isEmpty {
                        self.updateStatus("No speech detected")
                    } else {
                        self.updateStatus("Ready")
                        Task {
                            await self.textInjector.inject(text: text)
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.isTranscribing = false
                    self.updateStatus("Error: \(error.localizedDescription)")
                }
            }
        }
    }

    private func cancelRecording() {
        guard isRecording else { return }
        _ = audioRecorder.stopRecording()
        isRecording = false
        updateStatusIcon(recording: false)
        updateStatus("Cancelled")
        playSound("Funk")
    }

    private func playSound(_ name: String) {
        NSSound(named: NSSound.Name(name))?.play()
    }
}

@main
enum Main {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AavazApp()
        app.delegate = delegate
        app.run()
    }
}
