import AppKit
@preconcurrency import AVFoundation

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
    private var transcribeAnimationTimer: Timer?

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

        hotkeyMonitor.start()

        Task {
            await autoDownloadModels()
        }
    }

    /// Auto-download tiny.en and base.en on first launch. Warn for medium.en.
    private func autoDownloadModels() async {
        let autoModels: [ModelManager.ModelName] = [.tinyEN, .baseEN]
        for model in autoModels {
            if !modelManager.isModelDownloaded(model) {
                updateStatus("Downloading \(model.rawValue)…")
                print("[Aavaz] Auto-downloading \(model.rawValue)")
                do {
                    try await modelManager.downloadModel(model) { [weak self] progress in
                        DispatchQueue.main.async {
                            self?.updateStatus("Downloading \(model.rawValue)… \(Int(progress * 100))%")
                        }
                    }
                    print("[Aavaz] Downloaded \(model.rawValue)")
                } catch {
                    print("[Aavaz] Failed to download \(model.rawValue): \(error)")
                    updateStatus("Failed to download \(model.rawValue)")
                }
            }
        }
        updateStatus("Ready")
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        setIconState(.idle)

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
                title: "  \(profile.name)",
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

        // Trigger key
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

    // MARK: - Icon States

    private enum IconState {
        case idle
        case recording
        case transcribing
    }

    private func setIconState(_ state: IconState) {
        stopAnimation()
        guard let button = statusItem?.button else { return }
        button.contentTintColor = nil

        switch state {
        case .idle:
            button.image = MenuBarIcon.idle()

        case .recording:
            startRecordingAnimation()

        case .transcribing:
            startTranscribeAnimation()
        }
    }

    private var animationFrameIndex = 0

    private func startRecordingAnimation() {
        guard let button = statusItem?.button else { return }
        animationFrameIndex = 0
        button.image = MenuBarIcon.recording(frame: 0)

        transcribeAnimationTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let button = self.statusItem?.button else { return }
                self.animationFrameIndex = (self.animationFrameIndex + 1) % MenuBarIcon.recordingFrameCount
                button.image = MenuBarIcon.recording(frame: self.animationFrameIndex)
            }
        }
    }

    private func startTranscribeAnimation() {
        guard let button = statusItem?.button else { return }
        animationFrameIndex = 0
        button.image = MenuBarIcon.transcribing(frame: 0)

        transcribeAnimationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let button = self.statusItem?.button else { return }
                self.animationFrameIndex = (self.animationFrameIndex + 1) % MenuBarIcon.transcribingFrameCount
                button.image = MenuBarIcon.transcribing(frame: self.animationFrameIndex)
            }
        }
    }

    private func stopAnimation() {
        transcribeAnimationTimer?.invalidate()
        transcribeAnimationTimer = nil
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
            DispatchQueue.main.async {
                self?.statusItem?.menu?.cancelTracking()
                self?.toggleRecording()
            }
        }
        hotkeyMonitor.onCancel = { [weak self] in
            DispatchQueue.main.async {
                self?.cancelRecording()
            }
        }
        hotkeyMonitor.onStatusChange = { [weak self] status in
            self?.updateStatus(status)
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

        // Warn for large models
        if modelName == .mediumEN {
            let alert = NSAlert()
            alert.messageText = "Download medium.en model?"
            alert.informativeText = "This model is ~1.5 GB and will take a while to download. It provides the highest quality transcription."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Download")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() != .alertFirstButtonReturn {
                return
            }
        }

        updateStatus("Downloading \(profile.modelName)…")

        Task {
            do {
                try await modelManager.downloadModel(modelName) { [weak self] progress in
                    DispatchQueue.main.async {
                        self?.updateStatus("Downloading \(profile.modelName)… \(Int(progress * 100))%")
                    }
                }
                updateStatus("Download complete")
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
        guard !isRecording, !isTranscribing else {
            print("[Aavaz] startRecording: already recording or transcribing")
            return
        }

        let profile = preferences.activeProfile
        guard let modelName = ModelManager.ModelName(rawValue: profile.modelName) else {
            print("[Aavaz] startRecording: invalid model name")
            return
        }

        if !modelManager.isModelDownloaded(modelName) {
            updateStatus("Model not downloaded — click Download Current Model…")
            playSound("Basso")
            print("[Aavaz] startRecording: model not downloaded")
            return
        }

        // Check mic permission BEFORE touching AVAudioEngine
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        print("[Aavaz] startRecording: mic permission status = \(micStatus.rawValue)")

        switch micStatus {
        case .authorized:
            doStartRecording()
        case .notDetermined:
            updateStatus("Requesting mic permission…")
            Task {
                let granted = await AudioRecorder.requestMicrophoneAccess()
                if granted {
                    doStartRecording()
                } else {
                    updateStatus("Microphone permission denied")
                    playSound("Basso")
                }
            }
        default:
            updateStatus("Microphone permission denied — check System Settings")
            playSound("Basso")
        }
    }

    private func doStartRecording() {
        print("[Aavaz] doStartRecording: starting AVAudioEngine…")
        do {
            try audioRecorder.startRecording()
            isRecording = true
            setIconState(.recording)
            updateStatus("Recording…")
            playSound("Tink")
            print("[Aavaz] doStartRecording: recording started")
        } catch {
            updateStatus("Recording failed: \(error.localizedDescription)")
            playSound("Basso")
            print("[Aavaz] doStartRecording: error = \(error)")
        }
    }

    private func stopRecordingAndTranscribe() {
        guard isRecording else { return }

        let audioBuffer = audioRecorder.stopRecording()
        isRecording = false
        setIconState(.idle)
        playSound("Pop")

        print("[Aavaz] stopRecording: got \(audioBuffer.count) samples (\(String(format: "%.1f", Double(audioBuffer.count) / 16000.0))s of audio)")

        guard !audioBuffer.isEmpty else {
            updateStatus("No audio recorded")
            return
        }

        isTranscribing = true
        setIconState(.transcribing)
        updateStatus("Transcribing…")

        let profile = preferences.activeProfile
        let modelPath = modelManager.modelPath(
            for: ModelManager.ModelName(rawValue: profile.modelName)!
        ).path
        print("[Aavaz] transcribing with model: \(modelPath)")

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
                print("[Aavaz] transcription result: \"\(text)\"")

                await MainActor.run {
                    self.isTranscribing = false
                    self.setIconState(.idle)
                    if text.isEmpty {
                        self.updateStatus("No speech detected")
                    } else {
                        print("[Aavaz] injecting text…")
                        Task {
                            let injected = await self.textInjector.inject(text: text)
                            if injected {
                                self.updateStatus("Ready")
                                print("[Aavaz] text injected")
                            } else {
                                self.updateStatus("Grant Accessibility in System Settings")
                                self.permissionManager.promptAccessibilityIfNeeded()
                            }
                        }
                    }
                }
            } catch {
                print("[Aavaz] transcription error: \(error)")
                await MainActor.run {
                    self.isTranscribing = false
                    self.setIconState(.idle)
                    self.updateStatus("Error: \(error.localizedDescription)")
                }
            }
        }
    }

    private func cancelRecording() {
        guard isRecording else { return }
        _ = audioRecorder.stopRecording()
        isRecording = false
        setIconState(.idle)
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
