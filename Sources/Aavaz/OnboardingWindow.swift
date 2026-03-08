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
    private var selectedProfileIndex = 0
    private var selectedKeyCode: UInt16 = 61
    private var selectedKeyName: String = "Right Option"

    // Callbacks
    var onComplete: ((_ profileIndex: Int, _ triggerKeyCode: UInt16) -> Void)?

    // References for permission buttons
    private var micButton: AccentButton?
    private var accessibilityButton: AccentButton?
    private var permissionManager: PermissionManager?

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

    func show(permissionManager: PermissionManager, preferences: Preferences) {
        // Close any existing panel first
        close()

        self.permissionManager = permissionManager
        self.selectedProfileIndex = preferences.activeProfileIndex
        self.selectedKeyCode = preferences.triggerKeyCode
        self.selectedKeyName = ShortcutRecorder.keyName(for: preferences.triggerKeyCode)

        let panelW: CGFloat = 480
        let panelH: CGFloat = 500

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
        panel.hidesOnDeactivate = false  // Don't hide when app loses focus
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
        case 2: renderReady(in: container)
        default: break
        }
    }

    // MARK: - Step 1: Welcome

    private func renderWelcome(in container: NSView) {
        let w = container.bounds.width

        // Waveform icon
        let waveformView = NSImageView(frame: NSRect(x: (w - 64) / 2, y: 320, width: 64, height: 64))
        if let sym = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 40, weight: .medium)
            waveformView.image = sym.withSymbolConfiguration(config)
            waveformView.contentTintColor = DesignTokens.accent
        }
        waveformView.imageAlignment = .alignCenter
        container.addSubview(waveformView)

        // Title
        let title = makeLabel("Welcome to Aavaz", font: DesignTokens.heading(size: 26), color: DesignTokens.text)
        title.frame = NSRect(x: 0, y: 265, width: w, height: 36)
        title.alignment = .center
        container.addSubview(title)

        // Subtitle
        let subtitle = makeLabel(
            "Voice to text, entirely on your Mac.\nFully local. No cloud. No latency.",
            font: DesignTokens.body(size: 14),
            color: DesignTokens.textSecondary
        )
        subtitle.frame = NSRect(x: 40, y: 210, width: w - 80, height: 44)
        subtitle.alignment = .center
        subtitle.maximumNumberOfLines = 2
        container.addSubview(subtitle)

        // Get Started button
        let btn = AccentButton(title: "Get Started", target: self, action: #selector(nextStep))
        btn.frame = NSRect(x: (w - 200) / 2, y: 140, width: 200, height: 44)
        container.addSubview(btn)

        addStepDots(to: container, current: 0)
    }

    // MARK: - Step 2: Setup

    private func renderSetup(in container: NSView) {
        let w = container.bounds.width
        let cardX: CGFloat = 40
        let cardW = w - 80

        // Title
        let title = makeLabel("Quick Setup", font: DesignTokens.heading(size: 22), color: DesignTokens.text)
        title.frame = NSRect(x: 0, y: 440, width: w, height: 30)
        title.alignment = .center
        container.addSubview(title)

        // --- Hotkey section ---
        let hotkeyLabel = makeLabel("Trigger Key", font: DesignTokens.label(size: 11), color: DesignTokens.textSecondary)
        hotkeyLabel.frame = NSRect(x: cardX, y: 406, width: cardW, height: 16)
        container.addSubview(hotkeyLabel)

        let hotkeyCard = makeCard(frame: NSRect(x: cardX, y: 368, width: cardW, height: 34))
        container.addSubview(hotkeyCard)

        let keyLabel = makeLabel("Double-tap  \(selectedKeyName)", font: .monospacedSystemFont(ofSize: 13, weight: .medium), color: DesignTokens.text)
        keyLabel.frame = NSRect(x: 12, y: 5, width: cardW - 100, height: 24)
        hotkeyCard.addSubview(keyLabel)

        let changeBtn = SecondaryButton(title: "Change", target: self, action: #selector(changeTriggerKey))
        changeBtn.frame = NSRect(x: cardW - 78, y: 4, width: 66, height: 26)
        hotkeyCard.addSubview(changeBtn)

        // --- Profile section ---
        let profileLabel = makeLabel("Transcription Profile", font: DesignTokens.label(size: 11), color: DesignTokens.textSecondary)
        profileLabel.frame = NSRect(x: cardX, y: 338, width: cardW, height: 16)
        container.addSubview(profileLabel)

        let profiles: [(String, String)] = [
            ("Fast", "Tiny model · < 1s latency"),
            ("Balanced", "Base model · Best for daily use"),
            ("Quality", "Medium model · Highest accuracy"),
        ]

        for (i, (name, desc)) in profiles.enumerated() {
            let y = CGFloat(296 - i * 36)
            let radio = NSButton(radioButtonWithTitle: "", target: self, action: #selector(selectProfile(_:)))
            radio.tag = i
            radio.frame = NSRect(x: cardX, y: y, width: 20, height: 28)
            radio.state = i == selectedProfileIndex ? .on : .off
            container.addSubview(radio)

            let nameLabel = makeLabel(name, font: DesignTokens.label(size: 14), color: DesignTokens.text)
            nameLabel.frame = NSRect(x: cardX + 24, y: y + 4, width: 90, height: 20)
            container.addSubview(nameLabel)

            let descLabel = makeLabel(desc, font: DesignTokens.body(size: 11), color: DesignTokens.textTertiary)
            descLabel.frame = NSRect(x: cardX + 114, y: y + 4, width: cardW - 114, height: 20)
            container.addSubview(descLabel)
        }

        // --- Permissions section ---
        let permLabel = makeLabel("Permissions", font: DesignTokens.label(size: 11), color: DesignTokens.textSecondary)
        permLabel.frame = NSRect(x: cardX, y: 178, width: cardW, height: 16)
        container.addSubview(permLabel)

        let micGranted = permissionManager?.isMicrophoneAuthorized() ?? false
        let micBtn = AccentButton(
            title: micGranted ? "✓  Microphone Granted" : "Grant Microphone Access",
            target: self,
            action: #selector(grantMicrophone)
        )
        micBtn.frame = NSRect(x: cardX, y: 140, width: cardW, height: 34)
        if micGranted {
            micBtn.enabled = false
            micBtn.alphaValue = 0.5
        }
        container.addSubview(micBtn)
        self.micButton = micBtn

        let axGranted = permissionManager?.isAccessibilityTrusted() ?? false
        let axBtn = AccentButton(
            title: axGranted ? "✓  Accessibility Granted" : "Grant Accessibility Access",
            target: self,
            action: #selector(grantAccessibility)
        )
        axBtn.frame = NSRect(x: cardX, y: 100, width: cardW, height: 34)
        if axGranted {
            axBtn.enabled = false
            axBtn.alphaValue = 0.5
        }
        container.addSubview(axBtn)
        self.accessibilityButton = axBtn

        // Continue button
        let btn = AccentButton(title: "Continue", target: self, action: #selector(nextStep))
        btn.frame = NSRect(x: (w - 200) / 2, y: 46, width: 200, height: 44)
        container.addSubview(btn)

        addStepDots(to: container, current: 1)

        // Poll for permission changes every 1.5s
        startPermissionPolling()
    }

    // MARK: - Step 3: Ready

    private func renderReady(in container: NSView) {
        let w = container.bounds.width

        // Animated waveform
        let waveformView = NSImageView(frame: NSRect(x: (w - 120) / 2, y: 310, width: 120, height: 60))
        waveformView.tag = 200
        waveformView.imageAlignment = .alignCenter
        container.addSubview(waveformView)

        animationFrame = 0
        waveformView.image = makeLargeWaveform(frame: 0)
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, let view = self.contentView?.viewWithTag(200) as? NSImageView else { return }
                self.animationFrame = (self.animationFrame + 1) % 8
                view.image = self.makeLargeWaveform(frame: self.animationFrame)
            }
        }

        // Title
        let title = makeLabel("You're All Set", font: DesignTokens.heading(size: 26), color: DesignTokens.text)
        title.frame = NSRect(x: 0, y: 260, width: w, height: 36)
        title.alignment = .center
        container.addSubview(title)

        // Instruction
        let instruction = makeLabel(
            "Double-tap \(selectedKeyName) to start recording.\nTap again to stop. Text appears at your cursor.",
            font: DesignTokens.body(size: 14),
            color: DesignTokens.textSecondary
        )
        instruction.frame = NSRect(x: 40, y: 200, width: w - 80, height: 48)
        instruction.alignment = .center
        instruction.maximumNumberOfLines = 3
        container.addSubview(instruction)

        // Done button
        let btn = AccentButton(title: "Done", target: self, action: #selector(finish))
        btn.frame = NSRect(x: (w - 200) / 2, y: 130, width: 200, height: 44)
        container.addSubview(btn)

        addStepDots(to: container, current: 2)
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

    @objc private func nextStep() {
        showStep(currentStep + 1)
    }

    @objc private func selectProfile(_ sender: NSButton) {
        selectedProfileIndex = sender.tag
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
        permissionManager?.promptAccessibility()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            let granted = self?.permissionManager?.isAccessibilityTrusted() ?? false
            self?.accessibilityButton?.title = granted ? "✓  Accessibility Granted" : "Grant Accessibility Access"
            self?.accessibilityButton?.enabled = !granted
            self?.accessibilityButton?.alphaValue = granted ? 0.5 : 1.0
            self?.accessibilityButton?.needsDisplay = true
        }
    }

    @objc private func finish() {
        stopAnimation()
        Self.markComplete()
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
            DispatchQueue.main.async {
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

    private func addStepDots(to container: NSView, current: Int) {
        let w = container.bounds.width
        let dotSize: CGFloat = 6
        let dotGap: CGFloat = 10
        let totalDots: CGFloat = 3
        let totalWidth = totalDots * dotSize + (totalDots - 1) * dotGap
        let startX = (w - totalWidth) / 2
        let y: CGFloat = 20

        for i in 0..<3 {
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

// MARK: - Custom Accent Button (no bezel, fully custom drawn)

final class AccentButton: NSView {
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
        layer?.cornerRadius = 10
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let bgColor = enabled ? DesignTokens.accent : DesignTokens.accent.withAlphaComponent(0.4)
        bgColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()

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
            _ = target?.perform(action)
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
            _ = target?.perform(action)
        }
    }
}
