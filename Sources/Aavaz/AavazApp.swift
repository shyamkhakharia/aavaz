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
    private var tapWindowMenuItems: [NSMenuItem] = []
    private var triggerKeyMenuItem: NSMenuItem?
    private let shortcutRecorder = ShortcutRecorder()

    // Available tap windows
    private let tapWindowOptions: [(String, TimeInterval)] = [
        ("200ms (fast)", 0.2),
        ("300ms (default)", 0.3),
        ("400ms (relaxed)", 0.4),
        ("500ms (slow)", 0.5),
    ]

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

        // Settings submenu
        let settingsItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        let settingsMenu = NSMenu()

        // Trigger key — press to record
        let triggerLabel = ShortcutRecorder.keyName(for: preferences.triggerKeyCode)
        let triggerItem = NSMenuItem(
            title: "Trigger Key: \(triggerLabel)  ⌄",
            action: #selector(openShortcutRecorder),
            keyEquivalent: ""
        )
        triggerItem.target = self
        settingsMenu.addItem(triggerItem)
        triggerKeyMenuItem = triggerItem

        // Tap window submenu
        let tapItem = NSMenuItem(title: "Double-Tap Speed", action: nil, keyEquivalent: "")
        let tapMenu = NSMenu()
        for (index, (label, window)) in tapWindowOptions.enumerated() {
            let item = NSMenuItem(title: label, action: #selector(selectTapWindow(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = abs(preferences.doubleTapWindow - window) < 0.01 ? .on : .off
            tapMenu.addItem(item)
            tapWindowMenuItems.append(item)
        }
        tapItem.submenu = tapMenu
        settingsMenu.addItem(tapItem)

        // Clipboard restore toggle
        settingsMenu.addItem(.separator())
        let clipboardItem = NSMenuItem(
            title: "Restore Clipboard After Paste",
            action: #selector(toggleClipboardRestore(_:)),
            keyEquivalent: ""
        )
        clipboardItem.target = self
        clipboardItem.state = preferences.restoreClipboard ? .on : .off
        settingsMenu.addItem(clipboardItem)

        settingsItem.submenu = settingsMenu
        menu.addItem(settingsItem)

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

    // MARK: - Menu Actions

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

    @objc private func openShortcutRecorder() {
        // Temporarily stop the hotkey monitor so it doesn't interfere
        hotkeyMonitor.stop()

        shortcutRecorder.onKeyRecorded = { [weak self] keyCode, name in
            guard let self else { return }
            self.preferences.triggerKeyCode = keyCode
            self.hotkeyMonitor.triggerKeyCode = keyCode
            try? self.prefsManager.save(self.preferences)
            self.triggerKeyMenuItem?.title = "Trigger Key: \(name)  ⌄"
            self.hotkeyMonitor.start()
        }
        shortcutRecorder.show()
    }

    @objc private func selectTapWindow(_ sender: NSMenuItem) {
        let index = sender.tag
        guard index >= 0, index < tapWindowOptions.count else { return }

        let (_, window) = tapWindowOptions[index]
        preferences.doubleTapWindow = window
        hotkeyMonitor.doubleTapWindow = window
        try? prefsManager.save(preferences)

        for (i, item) in tapWindowMenuItems.enumerated() {
            item.state = i == index ? .on : .off
        }
    }

    @objc private func toggleClipboardRestore(_ sender: NSMenuItem) {
        preferences.restoreClipboard.toggle()
        textInjector.restoreClipboard = preferences.restoreClipboard
        sender.state = preferences.restoreClipboard ? .on : .off
        try? prefsManager.save(preferences)
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
                updateStatus("Download complete ✓")
            } catch {
                updateStatus("Download failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Recording

    private func toggleRecording() {
        if isRecording {
            stopRecordingAndTranscribe()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        guard !isRecording, !isTranscribing else { return }

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
