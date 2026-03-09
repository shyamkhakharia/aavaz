import AppKit

@MainActor
final class OnboardingWindow {
    private static let onboardingCompleteKey = "onboardingComplete"

    static var isOnboardingComplete: Bool {
        UserDefaults.standard.bool(forKey: onboardingCompleteKey)
    }

    static func markComplete() {
        UserDefaults.standard.set(true, forKey: onboardingCompleteKey)
    }

    private var panel: NSPanel?
    private var currentStep = 0
    private var contentView: NSView?

    // User selections
    private var selectedProfileIndex = 1  // Base (Balanced) is recommended
    private var selectedKeyCode: UInt16 = 61
    private var selectedKeyName: String = "Right Option"

    // Callbacks
    var onComplete: ((_ profileIndex: Int, _ triggerKeyCode: UInt16) -> Void)?
    /// Called when onboarding finishes with still-active downloads so the app can track them
    var onHandoffDownloads: ((_ downloads: [ModelManager.ModelName: Task<Void, Never>]) -> Void)?
    /// Called during downloads so the app can track progress even while onboarding is open
    var onDownloadProgress: ((_ model: ModelManager.ModelName, _ progress: Double) -> Void)?
    /// Called when a download completes
    var onDownloadComplete: ((_ model: ModelManager.ModelName) -> Void)?

    // References for permission buttons
    private var micButton: AccentButton?
    private var accessibilityButton: AccentButton?
    private var permissionManager: PermissionManager?

    // Model download
    private var modelManager: ModelManager?
    private var modelButtons: [ModelManager.ModelName: AccentButton] = [:]
    private var modelStatusLabels: [ModelManager.ModelName: NSTextField] = [:]
    private var activeDownloads: Set<ModelManager.ModelName> = []
    private var downloadTasks: [ModelManager.ModelName: Task<Void, Never>] = [:]
    // When a card is selected but needs download, store the index to auto-start after re-render
    private var pendingDownloadIndex: Int?

    // Animation
    private var animationTimer: Timer?
    private var animationFrame = 0

    // Permission polling
    private var permissionPollTimer: Timer?

    // Keep ShortcutRecorder alive during key capture
    private var shortcutRecorder: ShortcutRecorder?

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func bringToFront() {
        guard let panel else { return }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        stopAnimation()
        stopPermissionPolling()
        panel?.close()
        panel = nil
        contentView = nil
    }

    func show(permissionManager: PermissionManager, modelManager: ModelManager, preferences: Preferences) {
        close()

        self.permissionManager = permissionManager
        self.modelManager = modelManager
        self.selectedProfileIndex = preferences.activeProfileIndex
        self.selectedKeyCode = preferences.triggerKeyCode
        self.selectedKeyName = ShortcutRecorder.keyName(for: preferences.triggerKeyCode)

        let panelW: CGFloat = 480
        let panelH: CGFloat = 540

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelW, height: panelH),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = ""
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.center()
        panel.backgroundColor = DesignTokens.bg
        panel.appearance = NSAppearance(named: .darkAqua)

        let container = NSView(frame: NSRect(x: 0, y: 0, width: panelW, height: panelH))
        panel.contentView = container
        self.contentView = container
        self.panel = panel

        showStep(0)

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Step Rendering

    private func showStep(_ step: Int) {
        currentStep = step
        stopAnimation()
        stopPermissionPolling()
        contentView?.subviews.forEach { $0.removeFromSuperview() }
        guard let container = contentView else { return }

        switch step {
        case 0: renderWelcome(in: container)
        case 1: renderSetup(in: container)
        case 2: renderModels(in: container)
        case 3: renderReady(in: container)
        default: break
        }

        if step > 0 {
            addBackChevron(to: container)
        }
    }

    // MARK: - Step 1: Welcome

    private func renderWelcome(in container: NSView) {
        let w = container.bounds.width

        // Waveform logo
        let waveformView = NSImageView(frame: NSRect(x: (w - 64) / 2, y: 370, width: 64, height: 64))
        if let sym = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 40, weight: .medium)
            waveformView.image = sym.withSymbolConfiguration(config)
            waveformView.contentTintColor = DesignTokens.accent
        }
        waveformView.imageAlignment = .alignCenter
        container.addSubview(waveformView)

        let title = makeLabel("Welcome to Aavaz", font: DesignTokens.heading(size: 26), color: DesignTokens.text)
        title.frame = NSRect(x: 0, y: 318, width: w, height: 36)
        title.alignment = .center
        container.addSubview(title)

        let subtitle = makeLabel(
            "Voice to text, entirely on your Mac.\nFully local. No cloud. No latency.",
            font: DesignTokens.body(size: 14),
            color: DesignTokens.textSecondary
        )
        subtitle.frame = NSRect(x: 40, y: 260, width: w - 80, height: 44)
        subtitle.alignment = .center
        subtitle.maximumNumberOfLines = 2
        container.addSubview(subtitle)

        let btn = AccentButton(title: "Get Started", target: self, action: #selector(nextStep))
        btn.frame = NSRect(x: (w - 200) / 2, y: 170, width: 200, height: 44)
        container.addSubview(btn)

        addStepDots(to: container, current: 0)
    }

    // MARK: - Step 2: Setup (hotkey + permissions)

    private func renderSetup(in container: NSView) {
        let w = container.bounds.width
        let cardX: CGFloat = 40
        let cardW = w - 80

        let title = makeLabel("Quick Setup", font: DesignTokens.heading(size: 22), color: DesignTokens.text)
        title.frame = NSRect(x: 0, y: 485, width: w, height: 30)
        title.alignment = .center
        container.addSubview(title)

        // --- Animated key tap demo ---
        let keySymbol = Self.keySymbol(for: selectedKeyName)
        let keyView = KeyTapView(keyLabel: keySymbol)
        keyView.frame = NSRect(x: (w - 120) / 2, y: 408, width: 120, height: 70)
        container.addSubview(keyView)

        animationFrame = 0
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.animationFrame += 1
                let phase = self.animationFrame % 8
                keyView.isPressed = (phase == 1 || phase == 3)
            }
        }

        let hotkeyExplain = makeLabel(
            "You'll double-tap this key to start dictating.\nTap again to stop — text will appear at your cursor.",
            font: DesignTokens.body(size: 12),
            color: DesignTokens.textSecondary
        )
        hotkeyExplain.frame = NSRect(x: cardX, y: 368, width: cardW, height: 34)
        hotkeyExplain.alignment = .center
        hotkeyExplain.maximumNumberOfLines = 2
        container.addSubview(hotkeyExplain)

        // Trigger key card
        let hotkeyCard = makeCard(frame: NSRect(x: cardX, y: 326, width: cardW, height: 36))
        container.addSubview(hotkeyCard)

        let keyLabel = makeLabel("Double-tap  \(selectedKeyName)", font: .monospacedSystemFont(ofSize: 13, weight: .medium), color: DesignTokens.text)
        keyLabel.frame = NSRect(x: 12, y: 6, width: cardW - 100, height: 24)
        hotkeyCard.addSubview(keyLabel)

        let changeBtn = SecondaryButton(title: "Change", target: self, action: #selector(changeTriggerKey))
        changeBtn.frame = NSRect(x: cardW - 78, y: 5, width: 66, height: 26)
        hotkeyCard.addSubview(changeBtn)

        // --- Permissions section ---
        let permLabel = makeLabel("Permissions", font: DesignTokens.label(size: 11), color: DesignTokens.textSecondary)
        permLabel.frame = NSRect(x: cardX, y: 280, width: cardW, height: 16)
        container.addSubview(permLabel)

        let micGranted = permissionManager?.isMicrophoneAuthorized() ?? false
        let micBtn = AccentButton(
            title: micGranted ? "✓  Microphone Granted" : "Grant Microphone Access",
            target: self,
            action: #selector(grantMicrophone)
        )
        micBtn.frame = NSRect(x: cardX, y: 234, width: cardW, height: 34)
        if micGranted { micBtn.enabled = false; micBtn.alphaValue = 0.5 }
        container.addSubview(micBtn)
        self.micButton = micBtn

        let micHint = makeLabel("So Aavaz can hear your voice", font: DesignTokens.body(size: 10), color: DesignTokens.textTertiary)
        micHint.frame = NSRect(x: cardX, y: 216, width: cardW, height: 14)
        micHint.alignment = .center
        container.addSubview(micHint)

        let axGranted = permissionManager?.isAccessibilityTrusted() ?? false
        let axBtn = AccentButton(
            title: axGranted ? "✓  Accessibility Granted" : "Grant Accessibility Access",
            target: self,
            action: #selector(grantAccessibility)
        )
        axBtn.frame = NSRect(x: cardX, y: 172, width: cardW, height: 34)
        if axGranted { axBtn.enabled = false; axBtn.alphaValue = 0.5 }
        container.addSubview(axBtn)
        self.accessibilityButton = axBtn

        let axHint = makeLabel("So Aavaz can type text at your cursor", font: DesignTokens.body(size: 10), color: DesignTokens.textTertiary)
        axHint.frame = NSRect(x: cardX, y: 154, width: cardW, height: 14)
        axHint.alignment = .center
        container.addSubview(axHint)

        let btn = AccentButton(title: "Continue", target: self, action: #selector(nextStep))
        btn.frame = NSRect(x: (w - 200) / 2, y: 46, width: 200, height: 44)
        container.addSubview(btn)

        addStepDots(to: container, current: 1)
        startPermissionPolling()
    }

    /// Map key name to a compact symbol for the key cap
    private static func keySymbol(for keyName: String) -> String {
        let lower = keyName.lowercased()
        if lower.contains("option") { return "⌥" }
        if lower.contains("command") || lower.contains("cmd") { return "⌘" }
        if lower.contains("control") || lower.contains("ctrl") { return "⌃" }
        if lower.contains("shift") { return "⇧" }
        if lower.contains("fn") || lower.contains("function") { return "fn" }
        if lower.contains("caps") { return "⇪" }
        if lower.contains("space") { return "␣" }
        // For named keys, use first few chars
        if keyName.count <= 3 { return keyName }
        return String(keyName.prefix(3))
    }

    // MARK: - Step 3: Choose & Download Models

    private static let modelOrder: [ModelManager.ModelName] = [.tinyEN, .baseEN, .mediumEN]

    private func renderModels(in container: NSView) {
        let w = container.bounds.width
        let cardX: CGFloat = 40
        let cardW = w - 80

        let title = makeLabel("Choose a Model", font: DesignTokens.heading(size: 22), color: DesignTokens.text)
        title.frame = NSRect(x: 0, y: 480, width: w, height: 30)
        title.alignment = .center
        container.addSubview(title)

        let explanation = makeLabel(
            "Choose a model to use for transcription.\nLarger models are more accurate but use more resources.",
            font: DesignTokens.body(size: 12),
            color: DesignTokens.textSecondary
        )
        explanation.frame = NSRect(x: cardX, y: 438, width: cardW, height: 34)
        explanation.alignment = .center
        explanation.maximumNumberOfLines = 2
        container.addSubview(explanation)

        let models: [(ModelManager.ModelName, String, String, String)] = [
            (.tinyEN, "Tiny", "~75 MB", "Fastest · < 1s latency"),
            (.baseEN, "Base", "~142 MB", "Balanced · Best for daily use"),
            (.mediumEN, "Medium", "~1.5 GB", "Highest accuracy · Slower"),
        ]

        modelButtons.removeAll()
        modelStatusLabels.removeAll()

        let cardHeight: CGFloat = 72
        let cardGap: CGFloat = 8

        for (i, (modelName, displayName, size, profile)) in models.enumerated() {
            let y = 356 - CGFloat(i) * (cardHeight + cardGap)
            let isSelected = i == selectedProfileIndex
            let card = makeCard(frame: NSRect(x: cardX, y: y, width: cardW, height: cardHeight))
            if isSelected {
                card.layer?.borderColor = DesignTokens.accent.cgColor
                card.layer?.borderWidth = 2
            }
            container.addSubview(card)

            // Radio indicator
            let radio = NSView(frame: NSRect(x: 14, y: (cardHeight - 18) / 2, width: 18, height: 18))
            radio.wantsLayer = true
            radio.layer?.cornerRadius = 9
            radio.layer?.borderWidth = 2
            radio.layer?.borderColor = (isSelected ? DesignTokens.accent : DesignTokens.textTertiary).cgColor
            if isSelected {
                let inner = NSView(frame: NSRect(x: 4, y: 4, width: 10, height: 10))
                inner.wantsLayer = true
                inner.layer?.cornerRadius = 5
                inner.layer?.backgroundColor = DesignTokens.accent.cgColor
                radio.addSubview(inner)
            }
            card.addSubview(radio)

            let nameLabel = makeLabel(displayName, font: DesignTokens.label(size: 15), color: DesignTokens.text)
            nameLabel.frame = NSRect(x: 42, y: 44, width: 100, height: 20)
            card.addSubview(nameLabel)

            // Recommended badge next to Base
            if i == 1 {
                let badge = makeLabel("Recommended", font: DesignTokens.label(size: 9), color: DesignTokens.accent)
                badge.frame = NSRect(x: 100, y: 48, width: 90, height: 14)
                card.addSubview(badge)
            }

            let sizeLabel = makeLabel(size, font: .monospacedSystemFont(ofSize: 11, weight: .regular), color: DesignTokens.accentLight)
            sizeLabel.frame = NSRect(x: 42, y: 28, width: 100, height: 16)
            card.addSubview(sizeLabel)

            let profileLabel = makeLabel(profile, font: DesignTokens.body(size: 11), color: DesignTokens.textSecondary)
            profileLabel.frame = NSRect(x: 42, y: 8, width: cardW - 160, height: 16)
            card.addSubview(profileLabel)

            let downloaded = modelManager?.isModelDownloaded(modelName) ?? false

            let btn = AccentButton(
                title: downloaded ? "Downloaded" : "Download",
                target: self,
                action: #selector(downloadModel(_:))
            )
            btn.frame = NSRect(x: cardW - 112, y: 22, width: 98, height: 28)
            btn.tag = i
            if downloaded { btn.enabled = false; btn.alphaValue = 0.5 }
            card.addSubview(btn)
            modelButtons[modelName] = btn

            let statusLabel = makeLabel("", font: DesignTokens.body(size: 10), color: DesignTokens.textSecondary)
            statusLabel.frame = NSRect(x: cardW - 112, y: 6, width: 98, height: 14)
            statusLabel.alignment = .center
            card.addSubview(statusLabel)
            modelStatusLabels[modelName] = statusLabel

            // Clickable area for selection (left side of card, not overlapping download button)
            let clickArea = CardClickArea(frame: NSRect(x: 0, y: 0, width: cardW - 116, height: cardHeight))
            clickArea.tag = i
            clickArea.target = self
            clickArea.action = #selector(selectModelCard(_:))
            card.addSubview(clickArea)
        }

        // Download All text link
        let allDownloaded = models.allSatisfy { modelManager?.isModelDownloaded($0.0) ?? false }
        if !allDownloaded {
            let downloadAllLink = ClickableLabel(
                text: "Download All Models",
                font: DesignTokens.label(size: 12),
                color: DesignTokens.accent,
                target: self,
                action: #selector(downloadAllModels)
            )
            downloadAllLink.sizeToFit()
            let linkSize = downloadAllLink.frame.size
            downloadAllLink.frame = NSRect(x: (w - linkSize.width) / 2, y: 92, width: linkSize.width, height: linkSize.height)
            container.addSubview(downloadAllLink)
        }

        let btn = AccentButton(title: "Continue", target: self, action: #selector(nextStep))
        btn.frame = NSRect(x: (w - 200) / 2, y: 46, width: 200, height: 40)
        container.addSubview(btn)

        addStepDots(to: container, current: 2)

        // Auto-start download if a card was clicked for an undownloaded model
        if let pending = pendingDownloadIndex {
            pendingDownloadIndex = nil
            let modelName = Self.modelOrder[pending]
            if let btn = modelButtons[modelName], btn.enabled {
                downloadModel(btn)
            }
        }
    }

    @objc private func selectModelCard(_ sender: CardClickArea) {
        let index = sender.tag
        guard index >= 0, index < Self.modelOrder.count else { return }
        let modelName = Self.modelOrder[index]
        selectedProfileIndex = index

        // If not downloaded and not already downloading, queue a download after re-render
        if let manager = modelManager, !manager.isModelDownloaded(modelName),
           !activeDownloads.contains(modelName) {
            pendingDownloadIndex = index
        }

        showStep(2)
    }

    @objc private func downloadModel(_ sender: AccentButton) {
        let index = sender.tag
        guard index >= 0, index < Self.modelOrder.count else { return }
        let modelName = Self.modelOrder[index]
        guard let manager = modelManager else { return }

        // If already downloading, cancel it
        if activeDownloads.contains(modelName) {
            downloadTasks[modelName]?.cancel()
            downloadTasks[modelName] = nil
            activeDownloads.remove(modelName)
            sender.title = "Download"
            sender.enabled = true
            sender.progress = 0
            sender.alphaValue = 1.0
            modelStatusLabels[modelName]?.stringValue = "Cancelled"
            modelStatusLabels[modelName]?.textColor = DesignTokens.textTertiary
            return
        }

        guard !manager.isModelDownloaded(modelName) else { return }

        sender.title = "0%"
        sender.enabled = true  // Keep enabled so user can tap to cancel
        sender.progress = 0.001
        activeDownloads.insert(modelName)
        selectedProfileIndex = index
        modelStatusLabels[modelName]?.stringValue = "Tap to cancel"
        modelStatusLabels[modelName]?.textColor = DesignTokens.textTertiary

        let task = Task {
            do {
                try await manager.downloadModel(modelName) { [weak self] progress in
                    Task { @MainActor in
                        let btn = self?.modelButtons[modelName]
                        btn?.title = "\(Int(progress * 100))%"
                        btn?.progress = progress
                        self?.onDownloadProgress?(modelName, progress)
                    }
                }
                activeDownloads.remove(modelName)
                downloadTasks[modelName] = nil
                let btn = modelButtons[modelName]
                btn?.title = "Downloaded"
                btn?.progress = 0
                btn?.enabled = false
                btn?.alphaValue = 0.5
                modelStatusLabels[modelName]?.stringValue = ""
                onDownloadComplete?(modelName)
                updateReadyDownloadStatus()
            } catch {
                activeDownloads.remove(modelName)
                downloadTasks[modelName] = nil
                if Task.isCancelled {
                    // Already handled in the cancel block above
                    return
                }
                let btn = modelButtons[modelName]
                btn?.title = "Retry"
                btn?.enabled = true
                btn?.progress = 0
                btn?.alphaValue = 1.0
                modelStatusLabels[modelName]?.stringValue = "Failed"
                modelStatusLabels[modelName]?.textColor = .systemRed
            }
        }
        downloadTasks[modelName] = task
    }

    private func updateReadyDownloadStatus() {
        guard currentStep == 3 else { return }
        if activeDownloads.isEmpty {
            contentView?.viewWithTag(201)?.removeFromSuperview()
        }
    }

    @objc private func downloadAllModels() {
        guard let manager = modelManager else { return }
        for (i, modelName) in Self.modelOrder.enumerated() {
            guard !manager.isModelDownloaded(modelName) else { continue }
            guard let btn = modelButtons[modelName], btn.enabled else { continue }
            btn.tag = i
            downloadModel(btn)
        }
    }

    // MARK: - Step 4: Ready

    private func renderReady(in container: NSView) {
        let w = container.bounds.width

        let waveformView = NSImageView(frame: NSRect(x: (w - 120) / 2, y: 360, width: 120, height: 60))
        waveformView.tag = 200
        waveformView.imageAlignment = .alignCenter
        container.addSubview(waveformView)

        animationFrame = 0
        waveformView.image = makeLargeWaveform(frame: 0)
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let view = self.contentView?.viewWithTag(200) as? NSImageView else { return }
                self.animationFrame = (self.animationFrame + 1) % 8
                view.image = self.makeLargeWaveform(frame: self.animationFrame)
            }
        }

        let title = makeLabel("You're All Set", font: DesignTokens.heading(size: 26), color: DesignTokens.text)
        title.frame = NSRect(x: 0, y: 310, width: w, height: 36)
        title.alignment = .center
        container.addSubview(title)

        let instruction = makeLabel(
            "Double-tap \(selectedKeyName) to start recording.\nTap again to stop. Text appears at your cursor.",
            font: DesignTokens.body(size: 14),
            color: DesignTokens.textSecondary
        )
        instruction.frame = NSRect(x: 40, y: 252, width: w - 80, height: 44)
        instruction.alignment = .center
        instruction.maximumNumberOfLines = 3
        container.addSubview(instruction)

        // Download status
        var btnY: CGFloat = 150
        if !activeDownloads.isEmpty {
            let dlStatus = makeLabel(
                "Model downloads are completing in the background.",
                font: DesignTokens.body(size: 12),
                color: DesignTokens.textTertiary
            )
            dlStatus.frame = NSRect(x: 40, y: 200, width: w - 80, height: 20)
            dlStatus.alignment = .center
            dlStatus.tag = 201
            container.addSubview(dlStatus)
            btnY = 140
        }

        let btn = AccentButton(title: "Done", target: self, action: #selector(finish))
        btn.frame = NSRect(x: (w - 200) / 2, y: btnY, width: 200, height: 44)
        container.addSubview(btn)

        addStepDots(to: container, current: 3)
    }

    // MARK: - Large waveform for Ready step

    private func makeLargeWaveform(frame: Int) -> NSImage {
        let patterns: [[Double]] = [
            [0.25, 0.50, 0.80, 1.00, 0.70, 0.40, 0.20],
            [0.40, 0.70, 0.55, 0.85, 1.00, 0.60, 0.30],
            [0.30, 0.90, 0.70, 0.50, 0.80, 1.00, 0.45],
            [0.50, 0.40, 1.00, 0.70, 0.55, 0.75, 0.60],
            [0.60, 0.80, 0.45, 0.90, 0.65, 0.35, 0.85],
            [0.35, 0.65, 0.90, 0.40, 1.00, 0.55, 0.50],
            [0.70, 0.35, 0.60, 0.80, 0.45, 0.90, 0.40],
            [0.45, 0.55, 0.75, 0.60, 0.35, 0.80, 0.70],
        ]
        let pattern = patterns[frame % patterns.count]
        let barCount = 7
        let size = NSSize(width: 120, height: 60)

        return NSImage(size: size, flipped: false) { rect in
            let barWidth: CGFloat = 3.0
            let gap: CGFloat = 6.0
            let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * gap
            let startX = (rect.width - totalWidth) / 2
            let maxHeight: CGFloat = 44.0
            let baseY = (rect.height - maxHeight) / 2

            DesignTokens.accent.setFill()

            for i in 0..<barCount {
                let height = max(4.0, pattern[i] * maxHeight)
                let x = startX + CGFloat(i) * (barWidth + gap)
                let y = baseY + (maxHeight - height) / 2
                let barRect = NSRect(x: x, y: y, width: barWidth, height: height)
                NSBezierPath(roundedRect: barRect, xRadius: 1.5, yRadius: 1.5).fill()
            }
            return true
        }
    }

    // MARK: - Actions

    @objc private func prevStep() {
        if currentStep > 0 { showStep(currentStep - 1) }
    }

    @objc private func nextStep() {
        // On the models page, require at least one model downloaded or downloading
        if currentStep == 2 {
            let selectedModel = Self.modelOrder[selectedProfileIndex]
            let isDownloaded = modelManager?.isModelDownloaded(selectedModel) ?? false
            let isDownloading = activeDownloads.contains(selectedModel)
            if !isDownloaded && !isDownloading {
                // Shake the Continue button to hint the user needs to download
                if let container = contentView {
                    for sub in container.subviews {
                        if let btn = sub as? AccentButton, btn.title == "Continue" {
                            let anim = CAKeyframeAnimation(keyPath: "position.x")
                            anim.values = [0, -8, 8, -6, 6, -3, 3, 0].map { btn.layer!.position.x + $0 }
                            anim.duration = 0.4
                            btn.layer?.add(anim, forKey: "shake")
                        }
                    }
                }
                return
            }
        }
        showStep(currentStep + 1)
    }

    @objc private func changeTriggerKey() {
        let recorder = ShortcutRecorder()
        self.shortcutRecorder = recorder
        recorder.onKeyRecorded = { [weak self] keyCode, name in
            guard let self else { return }
            self.selectedKeyCode = keyCode
            self.selectedKeyName = name
            self.shortcutRecorder = nil
            self.showStep(1)
        }
        recorder.show()
    }

    @objc private func grantMicrophone() {
        Task {
            await permissionManager?.requestMicrophoneIfNeeded()
            let granted = permissionManager?.isMicrophoneAuthorized() ?? false
            micButton?.title = granted ? "✓  Microphone Granted" : "Grant Microphone Access"
            micButton?.enabled = !granted
            micButton?.alphaValue = granted ? 0.5 : 1.0
            micButton?.needsDisplay = true
        }
    }

    @objc private func grantAccessibility() {
        // This registers the app in the Accessibility list for the current binary signature
        let trusted = AXIsProcessTrustedWithOptions(
            ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary
        )
        // Also open System Settings as convenience (prompt: true already shows a dialog,
        // but the Settings pane lets users toggle the switch directly)
        if !trusted {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @objc private func finish() {
        stopAnimation()
        Self.markComplete()
        // Hand off any still-running downloads to the app
        if !downloadTasks.isEmpty {
            onHandoffDownloads?(downloadTasks)
        }
        onComplete?(selectedProfileIndex, selectedKeyCode)
        panel?.close()
        panel = nil
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func startPermissionPolling() {
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPermissionButtons()
            }
        }
    }

    private func stopPermissionPolling() {
        permissionPollTimer?.invalidate()
        permissionPollTimer = nil
    }

    private func refreshPermissionButtons() {
        let micGranted = permissionManager?.isMicrophoneAuthorized() ?? false
        if let btn = micButton {
            btn.title = micGranted ? "✓  Microphone Granted" : "Grant Microphone Access"
            btn.enabled = !micGranted
            btn.alphaValue = micGranted ? 0.5 : 1.0
            btn.needsDisplay = true
        }

        let axGranted = permissionManager?.isAccessibilityTrusted() ?? false
        if let btn = accessibilityButton {
            btn.title = axGranted ? "✓  Accessibility Granted" : "Grant Accessibility Access"
            btn.enabled = !axGranted
            btn.alphaValue = axGranted ? 0.5 : 1.0
            btn.needsDisplay = true
        }
    }

    // MARK: - UI Helpers

    private func makeLabel(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        label.drawsBackground = false
        return label
    }

    private func makeCard(frame: NSRect) -> NSView {
        let view = NSView(frame: frame)
        view.wantsLayer = true
        view.layer?.backgroundColor = DesignTokens.bgCard.cgColor
        view.layer?.borderColor = DesignTokens.border.cgColor
        view.layer?.borderWidth = 1
        view.layer?.cornerRadius = DesignTokens.radiusSmall
        return view
    }

    private func addBackChevron(to container: NSView) {
        let chevron = BackChevron(target: self, action: #selector(prevStep))
        // Well below traffic lights, bigger hit target
        chevron.frame = NSRect(x: 14, y: container.bounds.height - 72, width: 40, height: 40)
        container.addSubview(chevron)
    }

    private func addStepDots(to container: NSView, current: Int) {
        let w = container.bounds.width
        let dotSize: CGFloat = 6
        let dotGap: CGFloat = 10
        let totalDots: CGFloat = 4
        let totalWidth = totalDots * dotSize + (totalDots - 1) * dotGap
        let startX = (w - totalWidth) / 2
        let y: CGFloat = 18

        for i in 0..<4 {
            let dot = NSView(frame: NSRect(
                x: startX + CGFloat(i) * (dotSize + dotGap),
                y: y,
                width: dotSize,
                height: dotSize
            ))
            dot.wantsLayer = true
            dot.layer?.cornerRadius = dotSize / 2
            dot.layer?.backgroundColor = (i == current ? DesignTokens.accent : DesignTokens.textTertiary).cgColor
            container.addSubview(dot)
        }
    }
}

// MARK: - Animated Key Tap View

private final class KeyTapView: NSView {
    private let keyLabel: String
    var isPressed: Bool = false {
        didSet { needsDisplay = true }
    }

    init(keyLabel: String) {
        self.keyLabel = keyLabel
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let keySize: CGFloat = 52
        let centerX = bounds.midX
        let centerY = bounds.midY

        // Draw key cap
        let pressOffset: CGFloat = isPressed ? 2 : 0
        let keyRect = NSRect(
            x: centerX - keySize / 2,
            y: centerY - keySize / 2 - pressOffset,
            width: keySize,
            height: keySize
        )

        // Shadow (less when pressed)
        if !isPressed {
            let shadowRect = keyRect.offsetBy(dx: 0, dy: -3)
            NSColor(white: 0, alpha: 0.4).setFill()
            NSBezierPath(roundedRect: shadowRect, xRadius: 10, yRadius: 10).fill()
        }

        // Key background
        let bgColor = isPressed
            ? DesignTokens.accent.withAlphaComponent(0.3)
            : DesignTokens.bgCard
        bgColor.setFill()
        NSBezierPath(roundedRect: keyRect, xRadius: 10, yRadius: 10).fill()

        // Key border
        let borderColor = isPressed ? DesignTokens.accent : DesignTokens.border
        borderColor.setStroke()
        let borderPath = NSBezierPath(roundedRect: keyRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        borderPath.lineWidth = isPressed ? 2 : 1
        borderPath.stroke()

        // Key label
        let textColor = isPressed ? DesignTokens.accent : DesignTokens.text
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .medium),
            .foregroundColor: textColor,
        ]
        let str = NSAttributedString(string: keyLabel, attributes: attrs)
        let size = str.size()
        let textX = centerX - size.width / 2
        let textY = centerY - size.height / 2 - pressOffset
        str.draw(at: NSPoint(x: textX, y: textY))

        // Empty — no ×2 indicator
    }
}

// MARK: - Back Chevron (in a rounded box)

private final class BackChevron: NSView {
    private weak var target: AnyObject?
    private let action: Selector
    private var isHovered = false

    init(target: AnyObject, action: Selector) {
        self.target = target
        self.action = action
        super.init(frame: .zero)
        wantsLayer = true

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        // Always show the rounded box
        let bgColor = isHovered ? DesignTokens.bgCard : DesignTokens.bgCard.withAlphaComponent(0.5)
        bgColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()

        let borderColor = isHovered ? DesignTokens.accent.withAlphaComponent(0.5) : DesignTokens.border
        borderColor.setStroke()
        let borderPath = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        borderPath.lineWidth = 1
        borderPath.stroke()

        // Draw chevron arrow using a path for crispness
        let arrowColor = isHovered ? DesignTokens.accentLight : DesignTokens.accent
        arrowColor.setStroke()
        let arrow = NSBezierPath()
        let cx = bounds.midX
        let cy = bounds.midY
        arrow.move(to: NSPoint(x: cx + 4, y: cy - 8))
        arrow.line(to: NSPoint(x: cx - 4, y: cy))
        arrow.line(to: NSPoint(x: cx + 4, y: cy + 8))
        arrow.lineWidth = 2.5
        arrow.lineCapStyle = .round
        arrow.lineJoinStyle = .round
        arrow.stroke()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        alphaValue = 0.5
    }

    override func mouseUp(with event: NSEvent) {
        alphaValue = 1.0
        let loc = convert(event.locationInWindow, from: nil)
        if bounds.contains(loc) {
            _ = target?.perform(action, with: self)
        }
    }
}

// MARK: - Clickable Label (text link style)

private final class ClickableLabel: NSTextField {
    private weak var clickTarget: AnyObject?
    private var clickAction: Selector?

    init(text: String, font: NSFont, color: NSColor, target: AnyObject, action: Selector) {
        self.clickTarget = target
        self.clickAction = action
        super.init(frame: .zero)
        self.stringValue = text
        self.font = font
        self.textColor = color
        self.backgroundColor = .clear
        self.isBezeled = false
        self.isEditable = false
        self.drawsBackground = false
        self.isSelectable = false

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func mouseEntered(with event: NSEvent) {
        let underlined = NSAttributedString(
            string: stringValue,
            attributes: [
                .font: font as Any,
                .foregroundColor: DesignTokens.accentLight,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ]
        )
        attributedStringValue = underlined
    }

    override func mouseExited(with event: NSEvent) {
        let normal = NSAttributedString(
            string: stringValue,
            attributes: [
                .font: font as Any,
                .foregroundColor: DesignTokens.accent,
            ]
        )
        attributedStringValue = normal
    }

    override func mouseDown(with event: NSEvent) {
        alphaValue = 0.6
    }

    override func mouseUp(with event: NSEvent) {
        alphaValue = 1.0
        let loc = convert(event.locationInWindow, from: nil)
        if bounds.contains(loc), let clickAction {
            _ = clickTarget?.perform(clickAction, with: self)
        }
    }
}

// MARK: - Card Click Area (invisible, captures clicks for model selection)

private final class CardClickArea: NSView {
    weak var target: AnyObject?
    var action: Selector?
    override var tag: Int {
        get { _tag }
        set { _tag = newValue }
    }
    private var _tag: Int = 0

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        if bounds.contains(loc), let action {
            _ = target?.perform(action, with: self)
        }
    }
}

// MARK: - Custom Accent Button (no bezel, fully custom drawn)

final class AccentButton: NSView {
    var title: String {
        didSet { needsDisplay = true }
    }
    var progress: Double = 0 {
        didSet { needsDisplay = true }
    }
    override var isFlipped: Bool { true }
    override var tag: Int {
        get { _tag }
        set { _tag = newValue }
    }
    private var _tag: Int = 0

    private weak var target: AnyObject?
    private let action: Selector

    init(title: String, target: AnyObject, action: Selector) {
        self.title = title
        self.target = target
        self.action = action
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let radius: CGFloat = 10

        if progress > 0 && progress < 1.0 {
            DesignTokens.accent.withAlphaComponent(0.2).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()

            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).addClip()
            DesignTokens.accent.setFill()
            let fillWidth = bounds.width * CGFloat(progress)
            NSRect(x: 0, y: 0, width: fillWidth, height: bounds.height).fill()
            NSGraphicsContext.restoreGraphicsState()
        } else {
            let bgColor = enabled ? DesignTokens.accent : DesignTokens.accent.withAlphaComponent(0.4)
            bgColor.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: DesignTokens.label(size: 14),
            .foregroundColor: NSColor.white,
        ]
        let str = NSAttributedString(string: title, attributes: attrs)
        let size = str.size()
        let x = (bounds.width - size.width) / 2
        let y = (bounds.height - size.height) / 2
        str.draw(at: NSPoint(x: x, y: y))
    }

    var enabled: Bool = true {
        didSet { needsDisplay = true }
    }

    override func mouseDown(with event: NSEvent) {
        guard enabled else { return }
        alphaValue = 0.7
    }

    override func mouseUp(with event: NSEvent) {
        guard enabled else { return }
        alphaValue = 1.0
        let loc = convert(event.locationInWindow, from: nil)
        if bounds.contains(loc) {
            _ = target?.perform(action, with: self)
        }
    }
}

// MARK: - Secondary Button (outline style)

private final class SecondaryButton: NSView {
    var title: String {
        didSet { needsDisplay = true }
    }
    override var isFlipped: Bool { true }

    private weak var target: AnyObject?
    private let action: Selector

    init(title: String, target: AnyObject, action: Selector) {
        self.title = title
        self.target = target
        self.action = action
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        DesignTokens.bgCard.setFill()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        path.fill()
        DesignTokens.border.setStroke()
        path.lineWidth = 1
        path.stroke()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: DesignTokens.label(size: 12),
            .foregroundColor: DesignTokens.text,
        ]
        let str = NSAttributedString(string: title, attributes: attrs)
        let size = str.size()
        let x = (bounds.width - size.width) / 2
        let y = (bounds.height - size.height) / 2
        str.draw(at: NSPoint(x: x, y: y))
    }

    override func mouseDown(with event: NSEvent) {
        alphaValue = 0.7
    }

    override func mouseUp(with event: NSEvent) {
        alphaValue = 1.0
        let loc = convert(event.locationInWindow, from: nil)
        if bounds.contains(loc) {
            _ = target?.perform(action, with: self)
        }
    }
}
