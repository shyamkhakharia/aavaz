import AppKit
@preconcurrency import AVFoundation

@MainActor
final class AavazApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
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
    private var permissionMenuItem: NSMenuItem?
    private let shortcutRecorder = ShortcutRecorder()
    private var onboardingWindow: OnboardingWindow?

    // Track active downloads and their progress
    private var activeDownloads: [ModelManager.ModelName: Double] = [:]
    private var downloadTasks: [ModelManager.ModelName: Task<Void, Never>] = [:]
    private var menuRefreshTimer: Timer?
    private var menuOpenRefreshTimer: Timer?
    private var lastRefreshTime: CFAbsoluteTime = 0
    // Model submenu items for lightweight updates
    private var modelSubMenuItems: [NSMenuItem] = []

    // Available tap windows
    private let tapWindowOptions: [(String, TimeInterval)] = [
        ("200ms (fast)", 0.2),
        ("300ms (default)", 0.3),
        ("400ms (relaxed)", 0.4),
        ("500ms (slow)", 0.5),
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        setAppIcon()
        preferences = prefsManager.load()
        setupMenuBar()
        configureFromPreferences()

        if !OnboardingWindow.isOnboardingComplete {
            showOnboarding()
        } else {
            hotkeyMonitor.start()
        }
    }

    /// Sets the app icon programmatically as a fallback when no .icns is bundled.
    private func setAppIcon() {
        // Check if bundle already has an icon
        if let _ = Bundle.main.path(forResource: "AppIcon", ofType: "icns") { return }

        let size: CGFloat = 512
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let bgPath = NSBezierPath(roundedRect: rect.insetBy(dx: 16, dy: 16), xRadius: 96, yRadius: 96)
            DesignTokens.accent.setFill()
            bgPath.fill()

            let barCount = 7
            let barWidth: CGFloat = 24
            let gap: CGFloat = 20
            let totalW = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * gap
            let startX = (rect.width - totalW) / 2
            let maxH: CGFloat = 280
            let centerY = rect.height / 2
            let heights: [CGFloat] = [0.30, 0.55, 0.80, 1.0, 0.75, 0.50, 0.25]

            NSColor.white.setFill()
            for i in 0..<barCount {
                let h = heights[i] * maxH
                let x = startX + CGFloat(i) * (barWidth + gap)
                let y = centerY - h / 2
                let barRect = NSRect(x: x, y: y, width: barWidth, height: h)
                NSBezierPath(roundedRect: barRect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
            }
            return true
        }
        NSApp.applicationIconImage = img
    }

    private func showOnboarding() {
        // If already showing, just bring to front
        if let existing = onboardingWindow, existing.isVisible {
            existing.bringToFront()
            return
        }

        // Close any previous instance
        onboardingWindow?.close()

        let onboarding = OnboardingWindow()
        onboarding.onDownloadProgress = { [weak self] modelName, progress in
            guard let self else { return }
            self.activeDownloads[modelName] = progress
            // Throttle UI refresh to ~1 per second
            let now = CFAbsoluteTimeGetCurrent()
            if now - self.lastRefreshTime > 1.0 {
                self.lastRefreshTime = now
                self.refreshDownloadUI()
            }
            if self.menuRefreshTimer == nil {
                self.startMenuRefreshTimer()
            }
        }
        onboarding.onDownloadComplete = { [weak self] modelName in
            guard let self else { return }
            self.activeDownloads.removeValue(forKey: modelName)
            self.downloadTasks.removeValue(forKey: modelName)
            self.rebuildMenu()
            self.stopMenuRefreshTimerIfIdle()
        }
        onboarding.onHandoffDownloads = { [weak self] tasks in
            guard let self else { return }
            // Take over references to still-running tasks
            for (modelName, task) in tasks {
                if self.activeDownloads[modelName] == nil {
                    self.activeDownloads[modelName] = 0
                }
                self.downloadTasks[modelName] = task
            }
            if !tasks.isEmpty {
                self.startMenuRefreshTimer()
                self.rebuildMenu()
            }
        }
        onboarding.onComplete = { [weak self] profileIndex, triggerKeyCode in
            guard let self else { return }
            self.preferences.activeProfileIndex = profileIndex
            self.preferences.triggerKeyCode = triggerKeyCode
            try? self.prefsManager.save(self.preferences)
            self.configureFromPreferences()

            // Rebuild menu to reflect downloaded models and selected profile
            self.rebuildMenu()

            self.hotkeyMonitor.start()
            if self.activeDownloads.isEmpty {
                self.updateStatus("Ready")
            } else {
                self.refreshDownloadUI()
            }
            self.onboardingWindow = nil
        }
        onboarding.show(permissionManager: permissionManager, modelManager: modelManager, preferences: preferences)
        self.onboardingWindow = onboarding
    }

    private static let menuModelOrder: [ModelManager.ModelName] = [.tinyEN, .baseEN, .mediumEN]
    private static let modelDisplayNames: [ModelManager.ModelName: String] = [
        .tinyEN: "Fast",
        .baseEN: "Balanced",
        .mediumEN: "Quality",
    ]

    private static func displayName(for model: ModelManager.ModelName) -> String {
        modelDisplayNames[model] ?? model.rawValue
    }

    /// Shared download logic — tracks progress, updates menu live, rebuilds on completion
    private func startDownload(for modelName: ModelManager.ModelName, autoSelectIndex: Int? = nil) {
        guard activeDownloads[modelName] == nil else { return } // already downloading

        activeDownloads[modelName] = 0
        rebuildMenu()
        startMenuRefreshTimer()
        updateStatus("Downloading \(Self.displayName(for: modelName)) model…")

        let task = Task {
            do {
                try await modelManager.downloadModel(modelName) { [weak self] progress in
                    Task { @MainActor in
                        self?.activeDownloads[modelName] = progress
                    }
                }
                activeDownloads.removeValue(forKey: modelName)
                downloadTasks.removeValue(forKey: modelName)
                if let index = autoSelectIndex {
                    preferences.activeProfileIndex = index
                    try? prefsManager.save(preferences)
                }
                updateStatus("Downloaded \(Self.displayName(for: modelName)) model")
                rebuildMenu()
                stopMenuRefreshTimerIfIdle()
            } catch {
                activeDownloads.removeValue(forKey: modelName)
                downloadTasks.removeValue(forKey: modelName)
                updateStatus("Failed: \(error.localizedDescription)")
                rebuildMenu()
                stopMenuRefreshTimerIfIdle()
            }
        }
        downloadTasks[modelName] = task
    }

    private func startMenuRefreshTimer() {
        guard menuRefreshTimer == nil else { return }
        menuRefreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.refreshDownloadUI()
            }
        }
    }

    private func stopMenuRefreshTimerIfIdle() {
        if activeDownloads.isEmpty {
            menuRefreshTimer?.invalidate()
            menuRefreshTimer = nil
            menuOpenRefreshTimer?.invalidate()
            menuOpenRefreshTimer = nil
        }
    }

    /// Single method that updates status text + all menu item titles from activeDownloads
    private func refreshDownloadUI() {
        guard !activeDownloads.isEmpty else { return }

        // Update status line — keep it clean
        if activeDownloads.count == 1, let (model, progress) = activeDownloads.first {
            updateStatus("Downloading \(Self.displayName(for: model)) model… \(Int(progress * 100))%")
        } else {
            // Multiple downloads — show count and overall progress
            let totalProgress = activeDownloads.values.reduce(0, +) / Double(activeDownloads.count)
            updateStatus("Downloading \(activeDownloads.count) models… \(Int(totalProgress * 100))%")
        }

        // Update profile items in place
        for (index, item) in profileMenuItems.enumerated() {
            guard index < Self.menuModelOrder.count, index < preferences.profiles.count else { continue }
            let modelName = Self.menuModelOrder[index]
            let profileName = preferences.profiles[index].name
            let downloaded = modelManager.isModelDownloaded(modelName)

            if let progress = activeDownloads[modelName] {
                item.title = "  \(profileName)  (downloading… \(Int(progress * 100))%)"
                item.state = .off
            } else if downloaded {
                item.title = "  \(profileName)"
                item.state = index == preferences.activeProfileIndex ? .on : .off
            } else {
                item.title = "  \(profileName)  (not downloaded)"
                item.state = .off
            }
        }

        // Update model submenu items in place
        let modelEntries: [(ModelManager.ModelName, String, String)] = [
            (.tinyEN, "Tiny", "~75 MB"),
            (.baseEN, "Base", "~142 MB"),
            (.mediumEN, "Medium", "~1.5 GB"),
        ]
        for (i, (modelName, label, size)) in modelEntries.enumerated() {
            guard i < modelSubMenuItems.count else { continue }
            let item = modelSubMenuItems[i]
            let downloaded = modelManager.isModelDownloaded(modelName)

            if let progress = activeDownloads[modelName] {
                item.title = "\(label)  —  Downloading… \(Int(progress * 100))%"
                item.action = nil
                item.isEnabled = false
                item.state = .off
            } else if downloaded {
                item.title = "\(label)  —  Ready"
                item.action = #selector(selectModelFromMenu(_:))
                item.target = self
                item.tag = i
                item.isEnabled = true
                item.state = i == preferences.activeProfileIndex ? .on : .off
            } else {
                item.title = "\(label)  —  Download (\(size))"
                item.action = #selector(downloadModelFromMenu(_:))
                item.target = self
                item.tag = i
                item.isEnabled = true
                item.state = .off
            }
        }
    }

    private func appIconImage() -> NSImage {
        let size: CGFloat = 64
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let bgPath = NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: 14, yRadius: 14)
            DesignTokens.accent.setFill()
            bgPath.fill()

            let barCount = 7
            let barWidth: CGFloat = 3.0
            let gap: CGFloat = 2.5
            let totalW = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * gap
            let startX = (rect.width - totalW) / 2
            let maxH: CGFloat = 36
            let centerY = rect.height / 2
            let heights: [CGFloat] = [0.30, 0.55, 0.80, 1.0, 0.75, 0.50, 0.25]

            NSColor.white.setFill()
            for i in 0..<barCount {
                let h = heights[i] * maxH
                let x = startX + CGFloat(i) * (barWidth + gap)
                let y = centerY - h / 2
                let barRect = NSRect(x: x, y: y, width: barWidth, height: h)
                NSBezierPath(roundedRect: barRect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
            }
            return true
        }
    }

    @objc private func selectModelFromMenu(_ sender: NSMenuItem) {
        let index = sender.tag
        guard index >= 0, index < Self.menuModelOrder.count else { return }
        preferences.activeProfileIndex = index
        updateStatus("Using \(Self.displayName(for: Self.menuModelOrder[index])) model")
        rebuildMenu()
    }

    @objc private func downloadModelFromMenu(_ sender: NSMenuItem) {
        let index = sender.tag
        guard index >= 0, index < Self.menuModelOrder.count else { return }
        let modelName = Self.menuModelOrder[index]

        guard !modelManager.isModelDownloaded(modelName), activeDownloads[modelName] == nil else { return }
        startDownload(for: modelName, autoSelectIndex: index)
    }

    private func setupMenuBar() {
        // Clear old menu item references
        profileMenuItems.removeAll()
        tapWindowMenuItems.removeAll()
        modelSubMenuItems.removeAll()

        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        }
        statusItem!.length = NSStatusItem.squareLength
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
            let modelName = Self.menuModelOrder[index]
            let downloaded = modelManager.isModelDownloaded(modelName)
            let downloading = activeDownloads[modelName] != nil
            let suffix: String
            if downloading {
                let pct = Int((activeDownloads[modelName] ?? 0) * 100)
                suffix = "  (downloading… \(pct)%)"
            } else if !downloaded {
                suffix = "  (not downloaded)"
            } else {
                suffix = ""
            }
            let item = NSMenuItem(
                title: "  \(profile.name)\(suffix)",
                action: #selector(selectProfile(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = index
            item.state = index == preferences.activeProfileIndex && downloaded ? .on : .off
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

        // Run Setup Again
        settingsMenu.addItem(.separator())
        let setupItem = NSMenuItem(
            title: "Run Setup Again…",
            action: #selector(runSetupAgain),
            keyEquivalent: ""
        )
        setupItem.target = self
        settingsMenu.addItem(setupItem)

        settingsItem.submenu = settingsMenu
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        // Models submenu
        let modelsItem = NSMenuItem(title: "Models", action: nil, keyEquivalent: "")
        let modelsMenu = NSMenu()

        let modelEntries: [(ModelManager.ModelName, String, String)] = [
            (.tinyEN, "Tiny", "~75 MB"),
            (.baseEN, "Base", "~142 MB"),
            (.mediumEN, "Medium", "~1.5 GB"),
        ]
        for (i, (modelName, label, size)) in modelEntries.enumerated() {
            let downloaded = modelManager.isModelDownloaded(modelName)
            let downloading = activeDownloads[modelName] != nil
            let isActive = i == preferences.activeProfileIndex && downloaded

            let item: NSMenuItem
            if downloaded {
                item = NSMenuItem(title: "\(label)  —  Ready", action: #selector(selectModelFromMenu(_:)), keyEquivalent: "")
                item.target = self
                item.tag = i
                item.state = isActive ? .on : .off
            } else if downloading {
                let pct = Int((activeDownloads[modelName] ?? 0) * 100)
                item = NSMenuItem(title: "\(label)  —  Downloading… \(pct)%", action: nil, keyEquivalent: "")
                item.isEnabled = false
            } else {
                item = NSMenuItem(title: "\(label)  —  Download (\(size))", action: #selector(downloadModelFromMenu(_:)), keyEquivalent: "")
                item.target = self
                item.tag = i
            }
            modelsMenu.addItem(item)
            modelSubMenuItems.append(item)
        }

        modelsItem.submenu = modelsMenu
        menu.addItem(modelsItem)

        // Grant Permissions (hidden by default, shown when needed)
        let permsItem = NSMenuItem(
            title: "⚠ Grant Accessibility Permission…",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        permsItem.target = self
        permsItem.isHidden = true
        menu.addItem(permsItem)
        permissionMenuItem = permsItem

        menu.addItem(.separator())

        // Quit
        let quit = NSMenuItem(title: "Quit Aavaz", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.image = nil
        menu.addItem(quit)

        menu.delegate = self
        statusItem?.menu = menu
    }

    private func rebuildMenu() {
        setupMenuBar()
    }

    // NSMenuDelegate — fast refresh while menu is visible
    func menuWillOpen(_ menu: NSMenu) {
        // Immediate refresh
        refreshDownloadUI()
        // Start fast polling while menu is open so user sees live %
        guard !activeDownloads.isEmpty, menuOpenRefreshTimer == nil else { return }
        menuOpenRefreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.refreshDownloadUI()
            }
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        menuOpenRefreshTimer?.invalidate()
        menuOpenRefreshTimer = nil
    }

    // MARK: - Icon States

    private enum IconState {
        case idle
        case recording
        case transcribing
        case error
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

        case .error:
            button.image = MenuBarIcon.error()
        }
    }

    private var animationFrameIndex = 0

    private func startRecordingAnimation() {
        guard let button = statusItem?.button else { return }
        animationFrameIndex = 0
        button.image = MenuBarIcon.recording(frame: 0)

        transcribeAnimationTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
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
            DispatchQueue.main.async {
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

    @objc private func openAccessibilitySettings() {
        permissionManager.resetAndPromptAccessibility()
    }

    private func showPermissionError() {
        setIconState(.error)
        updateStatus("Accessibility permission required")
        permissionMenuItem?.isHidden = false
    }

    private func clearPermissionError() {
        permissionMenuItem?.isHidden = true
    }

    @objc private func selectProfile(_ sender: NSMenuItem) {
        let index = sender.tag
        guard index >= 0, index < preferences.profiles.count else { return }

        let modelName = Self.menuModelOrder[index]

        // If already downloading, do nothing
        if activeDownloads[modelName] != nil { return }

        // If model not downloaded, confirm download with user
        if !modelManager.isModelDownloaded(modelName) {
            let sizes: [ModelManager.ModelName: String] = [.tinyEN: "~75 MB", .baseEN: "~142 MB", .mediumEN: "~1.5 GB"]
            let size = sizes[modelName] ?? ""
            let alert = NSAlert()
            alert.icon = appIconImage()
            alert.messageText = "Download Required"
            alert.informativeText = "The \(preferences.profiles[index].name) model needs to be downloaded (\(size)). Download now?"
            alert.addButton(withTitle: "Download")
            alert.addButton(withTitle: "Cancel")
            alert.alertStyle = .informational

            let response = alert.runModal()
            guard response == .alertFirstButtonReturn else { return }

            startDownload(for: modelName, autoSelectIndex: index)
            return
        }

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

    @objc private func runSetupAgain() {
        hotkeyMonitor.stop()
        showOnboarding()
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
        guard let modelName = ModelManager.ModelName(rawValue: profile.modelName) else {
            updateStatus("Unknown model")
            isTranscribing = false
            setIconState(.idle)
            return
        }
        let modelPath = modelManager.modelPath(for: modelName).path
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
                                self.clearPermissionError()
                                self.updateStatus("Ready")
                                print("[Aavaz] text injected")
                            } else {
                                self.showPermissionError()
                                print("[Aavaz] paste failed — text is on clipboard, Cmd+V manually")
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
