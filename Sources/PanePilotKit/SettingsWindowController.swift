import AppKit
import Foundation

// MARK: - Layout Constants

/// Fixed content size for the Settings window. All tabs share the same dimensions so the
/// window does not resize when the user switches tabs.
private let settingsWindowContentSize = NSSize(width: 450, height: 300)
private let settingsVisibleTableRows = 7
private let settingsTableRowHeight: CGFloat = 30
private let shortcutControlHeight: CGFloat = 24
private let shortcutControlWidth: CGFloat = 180
private let shortcutControlCornerRadius: CGFloat = 7
private let shortcutClearWidth: CGFloat = 32
private let layoutRowPasteboardType = NSPasteboard.PasteboardType("com.panepilot.layout-row")
private let layoutOverlayControlAlpha: CGFloat = 0.72
private let layoutOverlayBorderAlpha: CGFloat = 0.45

@MainActor
private func secondaryLabel(_ text: String = "") -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: text)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.textColor = .secondaryLabelColor
    label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    return label
}

@MainActor
private func applyShortcutControlStyle(to view: NSView) {
    view.wantsLayer = true
    view.layer?.cornerRadius = shortcutControlCornerRadius
    view.layer?.backgroundColor = NSColor(calibratedWhite: 0.91, alpha: 1).cgColor
    view.layer?.borderWidth = 0
}

@MainActor
private func applyShortcutRecorderStyle(to button: NSButton) {
    button.bezelStyle = .regularSquare
    button.isBordered = false
    button.focusRingType = .none
    button.alignment = .center
    button.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    applyShortcutControlStyle(to: button)
}

@MainActor
private final class ShortcutValuePill: NSView {
    var onClear: (() -> Void)?

    private let valueContainer = NSView()
    private let label = NSTextField(labelWithString: "")
    private let clearButton = NSButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setValue(_ value: String, clearAccessibilityLabel: String) {
        label.stringValue = value
        clearButton.setAccessibilityLabel(clearAccessibilityLabel)
        clearButton.toolTip = clearAccessibilityLabel
    }

    private func configure() {
        applyShortcutControlStyle(to: self)

        valueContainer.translatesAutoresizingMaskIntoConstraints = false
        valueContainer.wantsLayer = true
        valueContainer.layer?.cornerRadius = shortcutControlCornerRadius
        valueContainer.layer?.backgroundColor = NSColor(calibratedWhite: 0.84, alpha: 1).cgColor

        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.lineBreakMode = .byTruncatingMiddle
        label.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        label.textColor = .labelColor

        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.isBordered = false
        clearButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Reset")
        clearButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        clearButton.contentTintColor = .secondaryLabelColor
        clearButton.toolTip = "Reset to default"
        clearButton.target = self
        clearButton.action = #selector(clear)

        addSubview(valueContainer)
        valueContainer.addSubview(label)
        addSubview(clearButton)

        NSLayoutConstraint.activate([
            valueContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            valueContainer.topAnchor.constraint(equalTo: topAnchor),
            valueContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
            valueContainer.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor),

            label.leadingAnchor.constraint(equalTo: valueContainer.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: valueContainer.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: valueContainer.centerYAnchor),

            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: shortcutClearWidth),
            clearButton.heightAnchor.constraint(equalTo: heightAnchor),
        ])
    }

    @objc
    private func clear() {
        onClear?()
    }
}

@MainActor
private final class CircularOverlayButton: NSButton {
    private let symbol = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Remove Divider")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        let diameter = min(bounds.width, bounds.height) - 2
        let circleRect = NSRect(
            x: bounds.midX - diameter / 2,
            y: bounds.midY - diameter / 2,
            width: diameter,
            height: diameter
        )

        let circle = NSBezierPath(ovalIn: circleRect)
        NSColor.windowBackgroundColor.withAlphaComponent(layoutOverlayControlAlpha).setFill()
        circle.fill()
        NSColor.systemRed.withAlphaComponent(0.72).setStroke()
        circle.lineWidth = 1
        circle.stroke()

        guard let symbol else { return }
        let iconSize = NSSize(width: 10, height: 10)
        let iconRect = NSRect(
            x: bounds.midX - iconSize.width / 2,
            y: bounds.midY - iconSize.height / 2,
            width: iconSize.width,
            height: iconSize.height
        )
        symbol.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 0.72)
    }

    private func configure() {
        bezelStyle = .regularSquare
        isBordered = false
        imagePosition = .imageOnly
        alignment = .center
        focusRingType = .none
        wantsLayer = false
        contentTintColor = .secondaryLabelColor
    }
}

@MainActor
private final class ShortcutRecorderButton: NSButton {
    var shortcut: KeyboardSnapShortcut? {
        didSet {
            recording = false
            updateTitle()
            onShortcutChanged?(shortcut)
        }
    }
    var onShortcutChanged: ((KeyboardSnapShortcut?) -> Void)?

    private var recording = false

    init(shortcut: KeyboardSnapShortcut?) {
        self.shortcut = shortcut
        super.init(frame: .zero)
        applyShortcutRecorderStyle(to: self)
        target = self
        action = #selector(startRecording)
        updateTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard recording else {
            super.keyDown(with: event)
            return
        }

        let modifiers = event.modifierFlags.intersection(KeyboardSnapShortcut.modifierMask)
        guard !modifiers.isEmpty else {
            NSSound.beep()
            return
        }

        shortcut = KeyboardSnapShortcut(modifiers: modifiers, keyCode: event.keyCode)
        window?.makeFirstResponder(nil)
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        updateTitle()
        return super.resignFirstResponder()
    }

    @objc
    private func startRecording() {
        recording = true
        title = "Press shortcut..."
        window?.makeFirstResponder(self)
    }

    private func updateTitle() {
        title = recording ? "Press..." : "Record Shortcut"
    }
}

@MainActor
private final class ModifierRecorderButton: NSButton {
    var modifier: DragSnapModifier? {
        didSet {
            recording = false
            updateTitle()
            onModifierChanged?(modifier)
        }
    }
    var onModifierChanged: ((DragSnapModifier?) -> Void)?

    private var recording = false
    private var pendingModifiers: NSEvent.ModifierFlags = []
    private var recordingRevision = 0

    init(modifier: DragSnapModifier?) {
        self.modifier = modifier
        super.init(frame: .zero)
        applyShortcutRecorderStyle(to: self)
        target = self
        action = #selector(startRecording)
        updateTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func flagsChanged(with event: NSEvent) {
        guard recording else {
            super.flagsChanged(with: event)
            return
        }

        let modifiers = event.modifierFlags.intersection(KeyboardSnapShortcut.modifierMask)
        guard !modifiers.isEmpty else { return }

        pendingModifiers = modifiers
        title = DragSnapModifier(modifiers: modifiers).displayName
        scheduleCommit()
    }

    override func keyDown(with event: NSEvent) {
        guard recording else {
            super.keyDown(with: event)
            return
        }
        NSSound.beep()
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        pendingModifiers = []
        recordingRevision += 1
        updateTitle()
        return super.resignFirstResponder()
    }

    @objc
    private func startRecording() {
        recording = true
        pendingModifiers = []
        recordingRevision += 1
        title = "Press modifiers..."
        window?.makeFirstResponder(self)
    }

    private func scheduleCommit() {
        recordingRevision += 1
        let revision = recordingRevision
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self, self.recording, self.recordingRevision == revision else { return }
            guard !self.pendingModifiers.isEmpty else { return }
            self.modifier = DragSnapModifier(modifiers: self.pendingModifiers)
            self.pendingModifiers = []
            self.window?.makeFirstResponder(nil)
        }
    }

    private func updateTitle() {
        title = recording ? "Press..." : "Record Modifier"
    }
}

/// AppKit window controller for the PanePilot Settings window.
///
/// The window hosts a tab bar with four tabs — General, Layouts, Debug, and About — each
/// backed by a dedicated private view-controller class. The window has a fixed content size
/// so tabs cannot cause resizing.
///
/// `SettingsWindowController` is created lazily by `SettingsWindowPresenter` and discarded
/// when the window closes. The presenter's `onWindowClosed` callback lets the presenter nil
/// out its reference and restore the `.accessory` activation policy.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    /// Called when the Settings window closes. Used by `SettingsWindowPresenter` to clean up.
    var onWindowClosed: (() -> Void)?

    private let tabController = SettingsTabViewController()
    private let generalViewController: GeneralSettingsViewController
    private let layoutsViewController: LayoutsSettingsViewController
    private let debugViewController: DebugSettingsViewController
    private let aboutViewController = AboutSettingsViewController()

    // MARK: - Initialization

    init(
        store: DisplayLayoutStore,
        initialSnapModifier: DragSnapModifier?,
        initialKeyboardSnapShortcut: KeyboardSnapShortcut?,
        onSnapModifierChanged: @escaping (DragSnapModifier?) -> Void,
        onKeyboardSnapShortcutChanged: @escaping (KeyboardSnapShortcut?) -> Void,
        onAccessibilityGranted: @escaping () -> Void,
        onDebugLoggingChanged: @escaping (Bool) -> Void
    ) {
        self.generalViewController = GeneralSettingsViewController(
            initialSnapModifier: initialSnapModifier,
            initialKeyboardSnapShortcut: initialKeyboardSnapShortcut,
            onSnapModifierChanged: onSnapModifierChanged,
            onKeyboardSnapShortcutChanged: onKeyboardSnapShortcutChanged,
            onAccessibilityGranted: onAccessibilityGranted
        )
        self.layoutsViewController = LayoutsSettingsViewController(store: store)
        self.debugViewController = DebugSettingsViewController(onDebugLoggingChanged: onDebugLoggingChanged)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: settingsWindowContentSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        super.init(window: window)

        configureWindow(window)
        configureTabs()
        wireEvents()

        tabController.preferredContentSize = settingsWindowContentSize
        window.contentViewController = tabController
        window.delegate = self
        window.setContentSize(settingsWindowContentSize)
        window.center()
        updateWindowTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Presentation

    func present() {
        refreshContent()
        updateWindowTitle()

        guard let window else { return }
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        applyFixedContentSize(to: window)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        DebugLogger.shared.info("Settings window closed.")
        onWindowClosed?()
    }

    // MARK: - Configuration

    private func configureWindow(_ window: NSWindow) {
        window.title = "General"
        window.contentMinSize = settingsWindowContentSize
        window.contentMaxSize = settingsWindowContentSize
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        applyFixedContentSize(to: window)
    }

    private func refreshContent() {
        generalViewController.refreshFromSystem()
        layoutsViewController.reloadLayouts(selectLayoutID: nil)
        debugViewController.refreshState()
    }

    private func configureTabs() {
        tabController.tabStyle = .toolbar
        tabController.onSelectionChanged = { [weak self] in
            self?.updateWindowTitle()
            if let window = self?.window {
                self?.applyFixedContentSize(to: window)
            }
        }

        tabController.addTabViewItem(
            makeTabItem(label: "General", symbolName: "gearshape", accessibilityDescription: "General", viewController: generalViewController)
        )
        tabController.addTabViewItem(
            makeTabItem(label: "Layouts", symbolName: "rectangle.split.3x1", accessibilityDescription: "Layouts", viewController: layoutsViewController)
        )
        tabController.addTabViewItem(
            makeTabItem(label: "Debug", symbolName: "waveform.path.ecg", accessibilityDescription: "Debug", viewController: debugViewController)
        )
        tabController.addTabViewItem(
            makeTabItem(label: "About", symbolName: "info.circle", accessibilityDescription: "About", viewController: aboutViewController)
        )
    }

    private func makeTabItem(
        label: String,
        symbolName: String,
        accessibilityDescription: String,
        viewController: NSViewController
    ) -> NSTabViewItem {
        let item = NSTabViewItem(viewController: viewController)
        item.label = label
        item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityDescription)
        return item
    }

    private func wireEvents() {
        layoutsViewController.onLayoutsChanged = { [weak self] selectedID in
            self?.layoutsViewController.reloadLayouts(selectLayoutID: selectedID)
        }
    }

    private func updateWindowTitle() {
        window?.title = tabController.tabView.selectedTabViewItem?.label ?? "Settings"
    }

    private func applyFixedContentSize(to window: NSWindow) {
        window.setContentSize(settingsWindowContentSize)
    }
}

@MainActor
private final class GeneralSettingsViewController: NSViewController {
    private let onSnapModifierChanged: (DragSnapModifier?) -> Void
    private let onKeyboardSnapShortcutChanged: (KeyboardSnapShortcut?) -> Void
    private let onAccessibilityGranted: () -> Void

    private let startAtLoginCheckbox = NSButton(checkboxWithTitle: "Start at Login", target: nil, action: nil)
    private let startAtLoginInfoLabel = NSTextField(wrappingLabelWithString: "Automatically opens the app when you start your Mac.")
    private let dragModifierLabel = NSTextField(labelWithString: "Drag Modifier")
    private let dragModifierValuePill = ShortcutValuePill(frame: .zero)
    private let dragModifierRecorder: ModifierRecorderButton
    private let dragModifierInfoLabel = NSTextField(wrappingLabelWithString: "")
    private let keyboardShortcutLabel = NSTextField(labelWithString: "Keyboard Snap")
    private let keyboardShortcutValuePill = ShortcutValuePill(frame: .zero)
    private let keyboardShortcutRecorder: ShortcutRecorderButton
    private let keyboardShortcutInfoLabel = NSTextField(wrappingLabelWithString: "")
    private var dragModifierRecorderLeadingToPill: NSLayoutConstraint?
    private var dragModifierRecorderLeadingToValueSlot: NSLayoutConstraint?
    private var dragModifierRecorderCompactWidth: NSLayoutConstraint?
    private var dragModifierRecorderWideWidth: NSLayoutConstraint?
    private var keyboardShortcutRecorderLeadingToPill: NSLayoutConstraint?
    private var keyboardShortcutRecorderLeadingToValueSlot: NSLayoutConstraint?
    private var keyboardShortcutRecorderCompactWidth: NSLayoutConstraint?
    private var keyboardShortcutRecorderWideWidth: NSLayoutConstraint?
    private let accessibilityCheckbox = NSButton(checkboxWithTitle: "Accessibility", target: nil, action: nil)
    private let dragModifierWarningIcon = NSImageView(frame: .zero)
    private let keyboardShortcutWarningIcon = NSImageView(frame: .zero)
    private var accessibilityPollTimer: Timer?
    private var accessibilityPollAttempts = 0
    private var accessibilityDistributedObserver: Any?

    // MARK: - Initialization

    init(
        initialSnapModifier: DragSnapModifier?,
        initialKeyboardSnapShortcut: KeyboardSnapShortcut?,
        onSnapModifierChanged: @escaping (DragSnapModifier?) -> Void,
        onKeyboardSnapShortcutChanged: @escaping (KeyboardSnapShortcut?) -> Void,
        onAccessibilityGranted: @escaping () -> Void
    ) {
        self.onSnapModifierChanged = onSnapModifierChanged
        self.onKeyboardSnapShortcutChanged = onKeyboardSnapShortcutChanged
        self.onAccessibilityGranted = onAccessibilityGranted
        self.dragModifierRecorder = ModifierRecorderButton(modifier: initialSnapModifier)
        self.keyboardShortcutRecorder = ShortcutRecorderButton(shortcut: initialKeyboardSnapShortcut)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - View Lifecycle

    override func loadView() {
        view = NSView()
        configureUI()
        refreshFromSystem()
        preferredContentSize = settingsWindowContentSize
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        accessibilityDistributedObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 100_000_000)
                self?.updateAccessibilityStatus()
            }
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        accessibilityPollTimer?.invalidate()
        accessibilityPollTimer = nil
        if let observer = accessibilityDistributedObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            accessibilityDistributedObserver = nil
        }
    }

    // MARK: - State

    func refreshFromSystem() {
        let available = LoginItemManager.shared.isFeatureAvailable
        startAtLoginCheckbox.isEnabled = available
        startAtLoginCheckbox.state = LoginItemManager.shared.isEnabled() ? .on : .off
        startAtLoginCheckbox.toolTip = available ? nil : LoginItemManager.shared.unavailableReason
        startAtLoginInfoLabel.textColor = available ? .secondaryLabelColor : .systemOrange
        startAtLoginInfoLabel.stringValue = available
            ? "Automatically opens the app when you start your Mac."
            : "Unavailable in this build. Use a signed app bundle to enable Start at Login."
        updateAccessibilityStatus()
    }

    // MARK: - Layout

    private func configureUI() {
        startAtLoginCheckbox.translatesAutoresizingMaskIntoConstraints = false
        startAtLoginCheckbox.target = self
        startAtLoginCheckbox.action = #selector(toggleStartAtLogin)

        startAtLoginInfoLabel.translatesAutoresizingMaskIntoConstraints = false
        startAtLoginInfoLabel.textColor = .secondaryLabelColor
        startAtLoginInfoLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)

        dragModifierLabel.translatesAutoresizingMaskIntoConstraints = false

        dragModifierValuePill.translatesAutoresizingMaskIntoConstraints = false
        dragModifierValuePill.onClear = { [weak self] in
            self?.clearDragModifier()
        }
        updateDragModifierValue()

        dragModifierRecorder.translatesAutoresizingMaskIntoConstraints = false
        dragModifierRecorder.toolTip = "Record Drag Modifier"
        dragModifierRecorder.onModifierChanged = { [weak self] modifier in
            self?.handleDragModifierChanged(modifier)
        }

        dragModifierInfoLabel.translatesAutoresizingMaskIntoConstraints = false
        dragModifierInfoLabel.textColor = .secondaryLabelColor
        dragModifierInfoLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        updateDragModifierInfo()

        keyboardShortcutLabel.translatesAutoresizingMaskIntoConstraints = false

        keyboardShortcutValuePill.translatesAutoresizingMaskIntoConstraints = false
        keyboardShortcutValuePill.onClear = { [weak self] in
            self?.clearKeyboardShortcut()
        }
        updateKeyboardShortcutValue()

        keyboardShortcutRecorder.translatesAutoresizingMaskIntoConstraints = false
        keyboardShortcutRecorder.onShortcutChanged = { [weak self] shortcut in
            self?.handleKeyboardShortcutChanged(shortcut)
        }

        keyboardShortcutInfoLabel.translatesAutoresizingMaskIntoConstraints = false
        keyboardShortcutInfoLabel.textColor = .secondaryLabelColor
        keyboardShortcutInfoLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        updateKeyboardShortcutInfo()

        accessibilityCheckbox.translatesAutoresizingMaskIntoConstraints = false
        accessibilityCheckbox.target = self
        accessibilityCheckbox.action = #selector(accessibilityCheckboxClicked)

        for icon in [dragModifierWarningIcon, keyboardShortcutWarningIcon] {
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Warning")
            icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            icon.contentTintColor = .systemOrange
            icon.isHidden = true
        }

        view.addSubview(startAtLoginCheckbox)
        view.addSubview(startAtLoginInfoLabel)
        view.addSubview(dragModifierLabel)
        view.addSubview(dragModifierValuePill)
        view.addSubview(dragModifierRecorder)
        view.addSubview(dragModifierInfoLabel)
        view.addSubview(keyboardShortcutLabel)
        view.addSubview(keyboardShortcutValuePill)
        view.addSubview(keyboardShortcutRecorder)
        view.addSubview(keyboardShortcutInfoLabel)
        view.addSubview(dragModifierWarningIcon)
        view.addSubview(keyboardShortcutWarningIcon)
        view.addSubview(accessibilityCheckbox)

        dragModifierRecorderLeadingToPill = dragModifierRecorder.leadingAnchor.constraint(
            equalTo: dragModifierValuePill.trailingAnchor,
            constant: 8
        )
        dragModifierRecorderLeadingToValueSlot = dragModifierRecorder.leadingAnchor.constraint(
            equalTo: dragModifierValuePill.leadingAnchor
        )
        dragModifierRecorderCompactWidth = dragModifierRecorder.widthAnchor.constraint(equalToConstant: 68)
        dragModifierRecorderWideWidth = dragModifierRecorder.widthAnchor.constraint(equalTo: dragModifierValuePill.widthAnchor)

        keyboardShortcutRecorderLeadingToPill = keyboardShortcutRecorder.leadingAnchor.constraint(
            equalTo: keyboardShortcutValuePill.trailingAnchor,
            constant: 8
        )
        keyboardShortcutRecorderLeadingToValueSlot = keyboardShortcutRecorder.leadingAnchor.constraint(
            equalTo: keyboardShortcutValuePill.leadingAnchor
        )
        keyboardShortcutRecorderCompactWidth = keyboardShortcutRecorder.widthAnchor.constraint(equalToConstant: 68)
        keyboardShortcutRecorderWideWidth = keyboardShortcutRecorder.widthAnchor.constraint(equalTo: keyboardShortcutValuePill.widthAnchor)

        NSLayoutConstraint.activate([
            startAtLoginCheckbox.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            startAtLoginCheckbox.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 80),

            startAtLoginInfoLabel.topAnchor.constraint(equalTo: startAtLoginCheckbox.bottomAnchor, constant: 8),
            startAtLoginInfoLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 80),
            startAtLoginInfoLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            dragModifierLabel.topAnchor.constraint(equalTo: startAtLoginInfoLabel.bottomAnchor, constant: 16),
            dragModifierLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 80),
            dragModifierLabel.centerYAnchor.constraint(equalTo: dragModifierValuePill.centerYAnchor),

            dragModifierValuePill.topAnchor.constraint(equalTo: startAtLoginInfoLabel.bottomAnchor, constant: 14),
            dragModifierValuePill.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 212),
            dragModifierValuePill.widthAnchor.constraint(equalToConstant: shortcutControlWidth),
            dragModifierValuePill.heightAnchor.constraint(equalToConstant: shortcutControlHeight),

            dragModifierRecorder.centerYAnchor.constraint(equalTo: dragModifierValuePill.centerYAnchor),
            dragModifierRecorder.heightAnchor.constraint(equalToConstant: shortcutControlHeight),

            dragModifierInfoLabel.topAnchor.constraint(equalTo: dragModifierValuePill.bottomAnchor, constant: 6),
            dragModifierInfoLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 80),
            dragModifierInfoLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            keyboardShortcutLabel.topAnchor.constraint(equalTo: dragModifierInfoLabel.bottomAnchor, constant: 12),
            keyboardShortcutLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 80),
            keyboardShortcutLabel.centerYAnchor.constraint(equalTo: keyboardShortcutValuePill.centerYAnchor),

            keyboardShortcutValuePill.topAnchor.constraint(equalTo: dragModifierInfoLabel.bottomAnchor, constant: 10),
            keyboardShortcutValuePill.leadingAnchor.constraint(equalTo: dragModifierValuePill.leadingAnchor),
            keyboardShortcutValuePill.widthAnchor.constraint(equalTo: dragModifierValuePill.widthAnchor),
            keyboardShortcutValuePill.heightAnchor.constraint(equalToConstant: shortcutControlHeight),

            keyboardShortcutRecorder.centerYAnchor.constraint(equalTo: keyboardShortcutValuePill.centerYAnchor),
            keyboardShortcutRecorder.heightAnchor.constraint(equalToConstant: shortcutControlHeight),

            keyboardShortcutInfoLabel.topAnchor.constraint(equalTo: keyboardShortcutValuePill.bottomAnchor, constant: 6),
            keyboardShortcutInfoLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 80),
            keyboardShortcutInfoLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            dragModifierWarningIcon.leadingAnchor.constraint(equalTo: dragModifierValuePill.trailingAnchor, constant: 8),
            dragModifierWarningIcon.centerYAnchor.constraint(equalTo: dragModifierValuePill.centerYAnchor),
            dragModifierWarningIcon.widthAnchor.constraint(equalToConstant: 16),
            dragModifierWarningIcon.heightAnchor.constraint(equalToConstant: 16),

            keyboardShortcutWarningIcon.leadingAnchor.constraint(equalTo: keyboardShortcutValuePill.trailingAnchor, constant: 8),
            keyboardShortcutWarningIcon.centerYAnchor.constraint(equalTo: keyboardShortcutValuePill.centerYAnchor),
            keyboardShortcutWarningIcon.widthAnchor.constraint(equalToConstant: 16),
            keyboardShortcutWarningIcon.heightAnchor.constraint(equalToConstant: 16),

            accessibilityCheckbox.topAnchor.constraint(equalTo: keyboardShortcutInfoLabel.bottomAnchor, constant: 14),
            accessibilityCheckbox.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 80),
        ])

        updateDragModifierControls()
        updateKeyboardShortcutControls()
    }

    // MARK: - Actions

    @objc
    private func toggleStartAtLogin() {
        do {
            try LoginItemManager.shared.setEnabled(startAtLoginCheckbox.state == .on)
            startAtLoginCheckbox.state = LoginItemManager.shared.isEnabled() ? .on : .off
        } catch {
            startAtLoginCheckbox.state = LoginItemManager.shared.isEnabled() ? .on : .off
        }
    }

    private func clearDragModifier() {
        dragModifierRecorder.modifier = nil
    }

    private func handleDragModifierChanged(_ modifier: DragSnapModifier?) {
        updateDragModifierValue()
        updateDragModifierInfo()
        updateDragModifierControls()
        onSnapModifierChanged(modifier)
    }

    private func updateDragModifierValue() {
        guard let modifier = dragModifierRecorder.modifier else { return }
        dragModifierValuePill.setValue(
            modifier.displayName,
            clearAccessibilityLabel: "Clear Drag Modifier"
        )
    }

    private func updateDragModifierInfo() {
        let modifier = dragModifierRecorder.modifier
        dragModifierInfoLabel.textColor = .secondaryLabelColor
        dragModifierInfoLabel.stringValue = modifier != nil
            ? "Hold this modifier while dragging to activate snap regions."
            : "Drag Snap is disabled until a modifier is recorded."
        let warning = modifier?.warningMessage
        dragModifierWarningIcon.isHidden = warning == nil
        dragModifierWarningIcon.toolTip = warning
    }

    private func updateDragModifierControls() {
        let hasModifier = dragModifierRecorder.modifier != nil
        dragModifierValuePill.isHidden = !hasModifier
        dragModifierRecorder.isHidden = hasModifier
        dragModifierRecorder.toolTip = hasModifier ? nil : "Record Drag Modifier"
        dragModifierRecorderLeadingToPill?.isActive = hasModifier
        dragModifierRecorderCompactWidth?.isActive = hasModifier
        dragModifierRecorderLeadingToValueSlot?.isActive = !hasModifier
        dragModifierRecorderWideWidth?.isActive = !hasModifier
    }

    @objc
    private func resetKeyboardShortcut() {
        keyboardShortcutRecorder.shortcut = .defaultShortcut
    }

    private func clearKeyboardShortcut() {
        keyboardShortcutRecorder.shortcut = nil
    }

    private func handleKeyboardShortcutChanged(_ shortcut: KeyboardSnapShortcut?) {
        updateKeyboardShortcutValue()
        updateKeyboardShortcutInfo()
        updateKeyboardShortcutControls()
        onKeyboardSnapShortcutChanged(shortcut)
    }

    private func updateKeyboardShortcutValue() {
        guard let shortcut = keyboardShortcutRecorder.shortcut else { return }
        keyboardShortcutValuePill.setValue(
            shortcut.displayName,
            clearAccessibilityLabel: "Clear Keyboard Snap shortcut"
        )
    }

    private func updateKeyboardShortcutControls() {
        let hasShortcut = keyboardShortcutRecorder.shortcut != nil
        keyboardShortcutValuePill.isHidden = !hasShortcut
        keyboardShortcutRecorder.isHidden = hasShortcut
        keyboardShortcutRecorder.toolTip = hasShortcut ? nil : "Record Keyboard Snap shortcut"
        keyboardShortcutRecorderLeadingToPill?.isActive = hasShortcut
        keyboardShortcutRecorderCompactWidth?.isActive = hasShortcut
        keyboardShortcutRecorderLeadingToValueSlot?.isActive = !hasShortcut
        keyboardShortcutRecorderWideWidth?.isActive = !hasShortcut
    }

    private func updateKeyboardShortcutInfo() {
        let shortcut = keyboardShortcutRecorder.shortcut
        keyboardShortcutInfoLabel.textColor = .secondaryLabelColor
        keyboardShortcutInfoLabel.stringValue = shortcut != nil
            ? "Opens the snap picker without dragging."
            : "Keyboard Snap is disabled until a shortcut is recorded."
        let warning = shortcut?.warningMessage
        keyboardShortcutWarningIcon.isHidden = warning == nil
        keyboardShortcutWarningIcon.toolTip = warning
    }

    @objc
    private func accessibilityCheckboxClicked() {
        let alreadyEnabled = PermissionManager().ensureAccessibilityPermission(prompt: false)
        updateAccessibilityStatus()  // immediately restore correct checkbox state
        if !alreadyEnabled {
            _ = PermissionManager().ensureAccessibilityPermission(prompt: true)
            startAccessibilityPolling()
        }
    }

    // macOS does not update the permission state synchronously when opening System Settings,
    // so the settings screen re-checks the flag after a short delay.
    private func updateAccessibilityStatus() {
        let enabled = PermissionManager().ensureAccessibilityPermission(prompt: false)
        accessibilityCheckbox.state = enabled ? .on : .off
        accessibilityCheckbox.title = enabled ? "Accessibility Enabled" : "Accessibility Not Enabled"
        if enabled {
            accessibilityPollTimer?.invalidate()
            accessibilityPollTimer = nil
            accessibilityPollAttempts = 0
        }
    }

    private func startAccessibilityPolling() {
        accessibilityPollTimer?.invalidate()
        accessibilityPollAttempts = 0
        accessibilityPollTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollAccessibilityStatus()
            }
        }
    }

    private func pollAccessibilityStatus() {
        accessibilityPollAttempts += 1
        let enabled = PermissionManager().ensureAccessibilityPermission(prompt: false)
        guard enabled else {
            if accessibilityPollAttempts >= 40 {
                accessibilityPollTimer?.invalidate()
                accessibilityPollTimer = nil
                accessibilityPollAttempts = 0
                updateAccessibilityStatus()
            }
            return
        }

        updateAccessibilityStatus()
        onAccessibilityGranted()
    }
}

private final class LayoutCatalogRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        let selectionRect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: selectionRect, xRadius: 6, yRadius: 6)
        NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
        path.fill()
    }
}

// Prevents AppKit from automatically making text white when a row is selected.
// The standard NSTableCellView backgroundStyle propagation inverts text to
// selectedMenuItemTextColor on emphasized rows, which is unreadable against our
// very-light custom selection fill.
private final class LayoutCatalogCellView: NSTableCellView {
    override var backgroundStyle: NSView.BackgroundStyle {
        get { super.backgroundStyle }
        set {}
    }
}

@MainActor
private final class LayoutsSettingsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    var onLayoutsChanged: ((String?) -> Void)?

    private let store: DisplayLayoutStore
    private var catalogItems: [LayoutCatalogItem] = []

    private let tableView = NSTableView(frame: .zero)
    private let scrollView = NSScrollView(frame: .zero)
    private let addButton = NSButton(title: "+", target: nil, action: nil)
    private let removeButton = NSButton(title: "-", target: nil, action: nil)
    private let previewView = LayoutPreviewView(frame: .zero)
    private let dividerHandleBadge = NSImageView(frame: .zero)
    private let mergeHandleButton = CircularOverlayButton(frame: .zero)
    private let statusLabel = secondaryLabel()
    private var isSynchronizingPreviewState = false
    private var dividerHandleCenterX: NSLayoutConstraint?
    private var dividerHandleCenterY: NSLayoutConstraint?
    private var mergeHandleCenterX: NSLayoutConstraint?
    private var mergeHandleCenterY: NSLayoutConstraint?
    private var activeLayoutIDForInteractiveResize: String?
    private var pendingInteractiveResize: (firstRegionIDs: [Int], secondRegionIDs: [Int], axis: SplitAxis, ratio: CGFloat)?

    // MARK: - Initialization

    init(store: DisplayLayoutStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - View Lifecycle

    override func loadView() {
        view = NSView()
        configureUI()
        reloadLayouts(selectLayoutID: nil)
        preferredContentSize = settingsWindowContentSize
    }

    // MARK: - Data Loading

    func reloadLayouts(selectLayoutID: String?) {
        let selectedID = selectLayoutID ?? selectedLayout?.id
        catalogItems = store.catalogItems()
        tableView.reloadData()

        if let selectedID,
           let idx = catalogItems.firstIndex(where: { $0.layout.id == selectedID }) {
            tableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
        } else if tableView.selectedRow < 0, !catalogItems.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }

        updateEditorForSelection()
    }

    // MARK: - Layout

    private func configureUI() {
        let layoutColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("layout"))
        layoutColumn.width = 198
        layoutColumn.resizingMask = .autoresizingMask
        tableView.addTableColumn(layoutColumn)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.headerView = nil
        tableView.style = .plain
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.rowHeight = settingsTableRowHeight
        tableView.intercellSpacing = .zero
        tableView.target = self
        tableView.doubleAction = #selector(handleTableDoubleClick)
        tableView.registerForDraggedTypes([layoutRowPasteboardType])
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)
        tableView.draggingDestinationFeedbackStyle = .gap
        tableView.allowsEmptySelection = false

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.wantsLayer = true
        scrollView.layer?.cornerRadius = 7
        scrollView.layer?.masksToBounds = true
        scrollView.borderType = .bezelBorder

        addButton.bezelStyle = .rounded
        addButton.title = ""
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add Layout")
        addButton.toolTip = "Add Layout"
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.target = self
        addButton.action = #selector(addLayout)

        removeButton.bezelStyle = .rounded
        removeButton.title = ""
        removeButton.image = NSImage(systemSymbolName: "minus", accessibilityDescription: "Remove Layout")
        removeButton.toolTip = "Remove Layout"
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        removeButton.target = self
        removeButton.action = #selector(removeLayout)

        previewView.translatesAutoresizingMaskIntoConstraints = false
        previewView.wantsLayer = true
        previewView.layer?.backgroundColor = NSColor.clear.cgColor
        previewView.onSelectionChanged = { [weak self] _ in
            guard let self, !self.isSynchronizingPreviewState else { return }
            self.updateEditorForSelection()
        }
        previewView.onDragSelectionChanged = { [weak self] _ in
            guard let self, !self.isSynchronizingPreviewState else { return }
            self.updateEditorForSelection()
        }
        previewView.onDividerRatioChanged = { [weak self] firstRegionIDs, secondRegionIDs, axis, ratio in
            self?.handleDividerRatioChanged(
                firstRegionIDs: firstRegionIDs,
                secondRegionIDs: secondRegionIDs,
                axis: axis,
                ratio: ratio
            )
        }
        previewView.onDividerInteractionEnded = { [weak self] firstRegionIDs, secondRegionIDs, axis, ratio in
            self?.handleDividerInteractionEnded(
                firstRegionIDs: firstRegionIDs,
                secondRegionIDs: secondRegionIDs,
                axis: axis,
                ratio: ratio
            )
        }
        previewView.onSplitRequested = { [weak self] regionID, axis, ratio in
            self?.handleSplitRequested(regionID: regionID, axis: axis, ratio: ratio)
        }

        dividerHandleBadge.translatesAutoresizingMaskIntoConstraints = false
        dividerHandleBadge.image = NSImage(systemSymbolName: "arrow.left.and.right", accessibilityDescription: "Resize Divider")
        dividerHandleBadge.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        dividerHandleBadge.wantsLayer = true
        dividerHandleBadge.layer?.cornerRadius = 5
        dividerHandleBadge.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(layoutOverlayControlAlpha).cgColor
        dividerHandleBadge.layer?.borderWidth = 1
        dividerHandleBadge.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(layoutOverlayBorderAlpha).cgColor
        dividerHandleBadge.contentTintColor = .secondaryLabelColor
        dividerHandleBadge.isHidden = true

        mergeHandleButton.translatesAutoresizingMaskIntoConstraints = false
        mergeHandleButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Remove Divider")
        mergeHandleButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
        mergeHandleButton.target = self
        mergeHandleButton.action = #selector(mergeSelectedRegions)
        mergeHandleButton.toolTip = "Remove Divider"
        mergeHandleButton.isHidden = true

        view.addSubview(scrollView)
        view.addSubview(addButton)
        view.addSubview(removeButton)
        view.addSubview(previewView)
        view.addSubview(dividerHandleBadge)
        view.addSubview(mergeHandleButton)
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            scrollView.widthAnchor.constraint(equalToConstant: 198),
            scrollView.heightAnchor.constraint(equalToConstant: compactTableHeight),

            addButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            addButton.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 6),
            addButton.widthAnchor.constraint(equalToConstant: 30),

            removeButton.leadingAnchor.constraint(equalTo: addButton.trailingAnchor, constant: 8),
            removeButton.centerYAnchor.constraint(equalTo: addButton.centerYAnchor),
            removeButton.widthAnchor.constraint(equalToConstant: 30),

            previewView.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            previewView.leadingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: 14),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            previewView.heightAnchor.constraint(equalToConstant: 160),

            statusLabel.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 10),
            statusLabel.leadingAnchor.constraint(equalTo: previewView.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: previewView.trailingAnchor),

            dividerHandleBadge.widthAnchor.constraint(equalToConstant: 20),
            dividerHandleBadge.heightAnchor.constraint(equalToConstant: 20),
            mergeHandleButton.widthAnchor.constraint(equalToConstant: 20),
            mergeHandleButton.heightAnchor.constraint(equalToConstant: 20),
        ])

        let dividerCenterX = dividerHandleBadge.centerXAnchor.constraint(equalTo: previewView.leadingAnchor, constant: 0)
        let dividerCenterY = dividerHandleBadge.centerYAnchor.constraint(equalTo: previewView.topAnchor, constant: 0)
        dividerCenterX.isActive = true
        dividerCenterY.isActive = true
        dividerHandleCenterX = dividerCenterX
        dividerHandleCenterY = dividerCenterY

        let centerX = mergeHandleButton.centerXAnchor.constraint(equalTo: previewView.leadingAnchor, constant: 0)
        let centerY = mergeHandleButton.centerYAnchor.constraint(equalTo: previewView.topAnchor, constant: 0)
        centerX.isActive = true
        centerY.isActive = true
        mergeHandleCenterX = centerX
        mergeHandleCenterY = centerY
    }

    private var compactTableHeight: CGFloat {
        CGFloat(settingsVisibleTableRows) * tableView.rowHeight
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int { catalogItems.count }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        LayoutCatalogRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < catalogItems.count, tableColumn?.identifier.rawValue == "layout" else { return nil }
        let item = catalogItems[row]
        let layout = item.layout
        let cell = LayoutCatalogCellView()

        let visibilityButton = NSButton()
        visibilityButton.translatesAutoresizingMaskIntoConstraints = false
        visibilityButton.image = NSImage(
            systemSymbolName: item.isVisible ? "eye" : "eye.slash",
            accessibilityDescription: item.isVisible ? "Visible in Picker" : "Hidden from Picker"
        )
        visibilityButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        visibilityButton.contentTintColor = rowIconColor(isVisible: item.isVisible)
        visibilityButton.isBordered = false
        visibilityButton.target = self
        visibilityButton.action = #selector(toggleVisibility)
        visibilityButton.toolTip = item.isVisible ? "Hide from Picker" : "Show in Picker"
        visibilityButton.setAccessibilityLabel(
            item.isVisible ? "Hide \(layout.name) from Picker" : "Show \(layout.name) in Picker"
        )
        visibilityButton.tag = row

        let field = NSTextField(string: layout.name)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        field.lineBreakMode = .byTruncatingTail
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        cell.addSubview(visibilityButton)
        cell.addSubview(field)
        cell.textField = field
        NSLayoutConstraint.activate([
            visibilityButton.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            visibilityButton.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            visibilityButton.widthAnchor.constraint(equalToConstant: 20),
            visibilityButton.heightAnchor.constraint(equalToConstant: 20),

            field.leadingAnchor.constraint(equalTo: visibilityButton.trailingAnchor, constant: 6),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])

        let editable = store.isLayoutEditable(id: layout.id)
        field.isEditable = editable
        field.isSelectable = true
        field.textColor = rowTextColor(isVisible: item.isVisible, isEditable: editable)
        field.delegate = self
        field.tag = row
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        tableView.needsDisplay = true
        updateEditorForSelection()
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard catalogItems.indices.contains(row) else { return nil }
        let item = NSPasteboardItem()
        item.setString(catalogItems[row].layout.id, forType: layoutRowPasteboardType)
        return item
    }

    func tableView(
        _ tableView: NSTableView,
        validateDrop info: NSDraggingInfo,
        proposedRow row: Int,
        proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        guard info.draggingSource as? NSTableView === tableView else { return [] }
        tableView.setDropRow(row, dropOperation: .above)
        return .move
    }

    func tableView(
        _ tableView: NSTableView,
        acceptDrop info: NSDraggingInfo,
        row: Int,
        dropOperation: NSTableView.DropOperation
    ) -> Bool {
        guard let layoutID = info.draggingPasteboard.string(forType: layoutRowPasteboardType),
              store.moveLayout(id: layoutID, to: row) else { return false }
        reloadLayouts(selectLayoutID: layoutID)
        onLayoutsChanged?(layoutID)
        return true
    }

    // MARK: - Actions

    @objc
    private func addLayout() {
        let layout = store.addFullscreenLayout(name: "")
        reloadLayouts(selectLayoutID: layout.id)
        onLayoutsChanged?(layout.id)
        if let row = catalogItems.firstIndex(where: { $0.layout.id == layout.id }) {
            tableView.editColumn(0, row: row, with: nil, select: true)
        }
    }

    @objc
    private func removeLayout() {
        let row = tableView.selectedRow
        guard row >= 0, row < catalogItems.count else { return }
        let layout = catalogItems[row].layout
        guard store.isLayoutEditable(id: layout.id) else { return }
        if store.removeLayout(id: layout.id) {
            reloadLayouts(selectLayoutID: nil)
            onLayoutsChanged?(nil)
        }
    }

    @objc
    private func toggleVisibility(_ sender: NSButton) {
        guard catalogItems.indices.contains(sender.tag) else { return }
        let item = catalogItems[sender.tag]
        guard store.setVisible(!item.isVisible, for: item.layout.id) else {
            NSSound.beep()
            reloadLayouts(selectLayoutID: item.layout.id)
            return
        }
        reloadLayouts(selectLayoutID: item.layout.id)
        onLayoutsChanged?(item.layout.id)
    }

    private func rowTextColor(isVisible: Bool, isEditable: Bool) -> NSColor {
        if !isVisible { return .tertiaryLabelColor }
        return isEditable ? .labelColor : .secondaryLabelColor
    }

    private func rowIconColor(isVisible: Bool) -> NSColor {
        isVisible ? .secondaryLabelColor : .tertiaryLabelColor
    }

    private func handleSplitRequested(regionID: Int, axis: SplitAxis, ratio: CGFloat) {
        guard let selectedLayout = selectedLayout else { return }
        guard store.isLayoutEditable(id: selectedLayout.id) else { return }

        guard let updated = store.splitRegion(layoutID: selectedLayout.id, regionID: regionID, axis: axis, ratio: ratio) else { return }
        reloadLayouts(selectLayoutID: updated.id)
        onLayoutsChanged?(updated.id)
    }

    @objc
    private func mergeSelectedRegions() {
        guard let selectedLayout = selectedLayout else { return }
        guard store.isLayoutEditable(id: selectedLayout.id) else { return }
        guard previewView.selectedRegionIDs.count == 2 else { return }

        let firstRegionID = previewView.selectedRegionIDs[0]
        let secondRegionID = previewView.selectedRegionIDs[1]
        guard let updated = store.mergeRegions(layoutID: selectedLayout.id, firstRegionID: firstRegionID, secondRegionID: secondRegionID) else {
            return
        }
        reloadLayouts(selectLayoutID: updated.id)
        onLayoutsChanged?(updated.id)
    }

    private var selectedLayout: RegionLayout? {
        let row = tableView.selectedRow
        guard row >= 0, row < catalogItems.count else { return nil }
        return catalogItems[row].layout
    }

    // MARK: - Preview Synchronization

    private func updateEditorForSelection() {
        guard let layout = selectedLayout else {
            synchronizePreviewState {
                previewView.layout = nil
            }
            removeButton.isEnabled = false
            removeButton.toolTip = "Select a custom layout to remove."
            dividerHandleBadge.isHidden = true
            mergeHandleButton.isHidden = true
            mergeHandleButton.isEnabled = false
            statusLabel.stringValue = ""
            return
        }

        synchronizePreviewState {
            previewView.layout = layout
            if previewView.selectedRegionIDs.isEmpty {
                previewView.selectedRegionIDs = layout.regions.first.map { [$0.id] } ?? []
            }
        }

        let editable = store.isLayoutEditable(id: layout.id)
        removeButton.isEnabled = editable
        removeButton.toolTip = editable
            ? "Remove Layout"
            : "Built-in layouts cannot be removed. Hide this layout using the eye icon."
        previewView.isEditableLayout = editable
        updateDividerHandle(for: layout, canEdit: editable)
        updateMergeHandle(for: layout, canEdit: editable)
    }

    private func selectedRegionStatus(for region: RegionLayout.Region) -> String {
        let width = region.normalizedFrame.width
        let height = region.normalizedFrame.height
        if width >= 0.995, height >= 0.995 {
            return "Full layout selected."
        }
        let w = Int((width * 100).rounded())
        let h = Int((height * 100).rounded())
        return "Region selected: \(w)% × \(h)%"
    }

    private func isMergeSelectionValid(for layout: RegionLayout) -> Bool {
        guard previewView.selectedRegionIDs.count == 2 else { return false }
        return store.canMergeRegions(
            layoutID: layout.id,
            firstRegionID: previewView.selectedRegionIDs[0],
            secondRegionID: previewView.selectedRegionIDs[1]
        )
    }

    // Prevent view callbacks from bouncing back into the controller while it is already
    // mutating preview selection or layout state in response to a previous callback.
    private func synchronizePreviewState(_ update: () -> Void) {
        isSynchronizingPreviewState = true
        defer { isSynchronizingPreviewState = false }
        update()
    }

    private func handleDividerRatioChanged(
        firstRegionIDs: [Int],
        secondRegionIDs: [Int],
        axis: SplitAxis,
        ratio: CGFloat
    ) {
        guard let layout = selectedLayout else { return }
        activeLayoutIDForInteractiveResize = layout.id
        pendingInteractiveResize = (firstRegionIDs, secondRegionIDs, axis, ratio)
        guard let updated = store.resizeAdjacentRegionGroups(
            layoutID: layout.id,
            firstRegionIDs: firstRegionIDs,
            secondRegionIDs: secondRegionIDs,
            axis: axis,
            ratio: ratio,
            persistChanges: false
        ) else { return }
        if let index = catalogItems.firstIndex(where: { $0.layout.id == updated.id }) {
            let item = catalogItems[index]
            catalogItems[index] = LayoutCatalogItem(
                layout: updated,
                isVisible: item.isVisible,
                isBuiltIn: item.isBuiltIn
            )
        }
        synchronizePreviewState {
            previewView.layout = updated
        }
        let editable = store.isLayoutEditable(id: updated.id)
        updateDividerHandle(for: updated, canEdit: editable)
        updateMergeHandle(for: updated, canEdit: editable)
    }

    private func handleDividerInteractionEnded(
        firstRegionIDs: [Int],
        secondRegionIDs: [Int],
        axis: SplitAxis,
        ratio: CGFloat
    ) {
        guard let layout = selectedLayout else { return }
        guard activeLayoutIDForInteractiveResize == layout.id || pendingInteractiveResize != nil else { return }
        _ = store.resizeAdjacentRegionGroups(
            layoutID: layout.id,
            firstRegionIDs: firstRegionIDs,
            secondRegionIDs: secondRegionIDs,
            axis: axis,
            ratio: ratio,
            persistChanges: true
        )
        pendingInteractiveResize = nil
        activeLayoutIDForInteractiveResize = nil
    }

    private func updateMergeHandle(for layout: RegionLayout, canEdit: Bool) {
        guard canEdit,
              previewView.selectedRegionIDs.count == 2,
              isMergeSelectionValid(for: layout),
              let point = previewView.selectedDividerPoint(),
              let axis = previewView.selectedDividerAxis() else {
            mergeHandleButton.isHidden = true
            mergeHandleButton.isEnabled = false
            return
        }

        let mergePoint: CGPoint
        switch axis {
        case .vertical:
            mergePoint = CGPoint(x: point.x, y: point.y + 26)
        case .horizontal:
            mergePoint = CGPoint(x: point.x - 26, y: point.y)
        }

        let yFromTop = max(0, previewView.bounds.height - mergePoint.y)
        mergeHandleCenterX?.constant = mergePoint.x
        mergeHandleCenterY?.constant = yFromTop
        mergeHandleButton.isHidden = false
        mergeHandleButton.isEnabled = true
    }

    private func updateDividerHandle(for layout: RegionLayout, canEdit: Bool) {
        guard canEdit,
              let point = previewView.selectedDividerPoint(),
              let axis = previewView.selectedDividerAxis() else {
            dividerHandleBadge.isHidden = true
            return
        }

        dividerHandleBadge.image = NSImage(
            systemSymbolName: axis == .vertical ? "arrow.left.and.right" : "arrow.up.and.down",
            accessibilityDescription: "Resize Divider"
        )
        let yFromTop = max(0, previewView.bounds.height - point.y)
        dividerHandleCenterX?.constant = point.x
        dividerHandleCenterY?.constant = yFromTop
        dividerHandleBadge.isHidden = false
    }

    @objc
    private func handleTableDoubleClick() {
        let row = tableView.clickedRow
        guard row >= 0, row < catalogItems.count else { return }
        let layout = catalogItems[row].layout
        guard store.isLayoutEditable(id: layout.id) else { return }
        tableView.editColumn(0, row: row, with: nil, select: true)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField else { return }
        let row = textField.tag
        guard row >= 0, row < catalogItems.count else { return }

        let layout = catalogItems[row].layout
        guard store.isLayoutEditable(id: layout.id) else {
            reloadLayouts(selectLayoutID: layout.id)
            return
        }

        if store.renameLayout(id: layout.id, to: textField.stringValue) {
            reloadLayouts(selectLayoutID: layout.id)
            onLayoutsChanged?(layout.id)
        } else {
            reloadLayouts(selectLayoutID: layout.id)
        }
    }
}

private final class LayoutPreviewView: NSView {
    private struct DividerHit {
        let firstRegionIDs: [Int]
        let secondRegionIDs: [Int]
        let axis: SplitAxis
        let lineRect: NSRect
        let touchRect: NSRect
        let ratioSpan: ClosedRange<CGFloat>

        var regionIDs: [Int] {
            firstRegionIDs + secondRegionIDs
        }
    }

    // MARK: - State

    var layout: RegionLayout? {
        didSet {
            if let layout {
                selectedRegionIDs = selectedRegionIDs.filter { selected in
                    layout.regions.contains(where: { $0.id == selected })
                }
                if selectedRegionIDs.isEmpty, let first = layout.regions.first?.id {
                    selectedRegionIDs = [first]
                }
            }
            needsDisplay = true
        }
    }

    var selectedRegionIDs: [Int] = [] {
        didSet {
            needsDisplay = true
            onSelectionChanged?(selectedRegionIDs)
        }
    }

    var primarySelectedRegionID: Int? {
        selectedRegionIDs.first
    }

    var onSelectionChanged: (([Int]) -> Void)?
    var onDragSelectionChanged: (([Int]) -> Void)?
    var onDividerRatioChanged: (([Int], [Int], SplitAxis, CGFloat) -> Void)?
    var onDividerInteractionEnded: (([Int], [Int], SplitAxis, CGFloat) -> Void)?
    var onSplitRequested: ((Int, SplitAxis, CGFloat) -> Void)?
    var isEditableLayout: Bool = false {
        didSet {
            needsDisplay = true
        }
    }
    private var activeDivider: DividerHit?
    private var currentDividerRatio: CGFloat?
    private var isDraggingSplitSource = false
    private var splitSourceDragPoint: NSPoint?
    private var pendingSplitDrop: (regionID: Int, axis: SplitAxis, ratio: CGFloat, lineRect: NSRect)?

    // MARK: - Selection Helpers

    func selectedDividerPoint() -> CGPoint? {
        selectedDividerHit().map { CGPoint(x: $0.lineRect.midX, y: $0.lineRect.midY) }
    }

    func selectedDividerAxis() -> SplitAxis? {
        selectedDividerHit()?.axis
    }

    private func selectedDividerHit() -> DividerHit? {
        guard let layout else { return nil }
        let selectedIDs = Set(selectedRegionIDs)
        return dividerHits(for: layout, in: bounds.insetBy(dx: 16, dy: 22))
            .first(where: { Set($0.regionIDs) == selectedIDs })
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let canvas = bounds.insetBy(dx: 8, dy: 8)

        let screenRect = canvas.insetBy(dx: 8, dy: 14)
        let path = NSBezierPath(roundedRect: screenRect, xRadius: 8, yRadius: 8)
        NSColor.controlAccentColor.withAlphaComponent(0.08).setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()

        guard let layout else { return }
        let dividers = dividerHits(for: layout, in: screenRect)
        for region in layout.regions {
            let r = rect(for: region.normalizedFrame, in: screenRect).insetBy(dx: 1, dy: 1)

            let regionPath = NSBezierPath(roundedRect: r, xRadius: 5, yRadius: 5)
            if selectedRegionIDs.contains(region.id) {
                NSColor.systemBlue.withAlphaComponent(isEditableLayout ? 0.28 : 0.26).setFill()
            } else {
                NSColor.systemGray.withAlphaComponent(0.18).setFill()
            }
            regionPath.fill()
            NSColor.separatorColor.setStroke()
            regionPath.lineWidth = 1
            regionPath.stroke()

            if let activeDivider,
               activeDivider.regionIDs.contains(region.id) {
                let label = displayPercentageLabel(for: region.normalizedFrame, axis: activeDivider.axis)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium),
                    .foregroundColor: NSColor.labelColor.withAlphaComponent(0.75),
                ]
                let textSize = label.size(withAttributes: attrs)
                let textRect = NSRect(
                    x: r.midX - (textSize.width / 2) - 4,
                    y: r.midY - (textSize.height / 2) - 2,
                    width: textSize.width + 8,
                    height: textSize.height + 4
                )
                if textRect.width < r.width - 6, textRect.height < r.height - 6 {
                    NSColor.windowBackgroundColor.withAlphaComponent(0.7).setFill()
                    NSBezierPath(roundedRect: textRect, xRadius: 4, yRadius: 4).fill()
                    (label as NSString).draw(
                        at: NSPoint(x: textRect.minX + 4, y: textRect.minY + 2),
                        withAttributes: attrs
                    )
                }
            }
        }

        if let activeDivider {
            NSColor.controlAccentColor.withAlphaComponent(0.28).setFill()
            NSBezierPath(roundedRect: activeDivider.lineRect.insetBy(dx: -2, dy: -2), xRadius: 4, yRadius: 4).fill()
        } else if let divider = dividers.first(where: { Set($0.regionIDs) == Set(selectedRegionIDs) }) {
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: divider.lineRect.insetBy(dx: -1, dy: -1), xRadius: 4, yRadius: 4).fill()
        }

        if let pendingSplitDrop {
            NSColor.controlAccentColor.withAlphaComponent(0.24).setFill()
            NSBezierPath(roundedRect: pendingSplitDrop.lineRect.insetBy(dx: -2, dy: -2), xRadius: 4, yRadius: 4).fill()
        }

        if isEditableLayout {
            drawParkedDividers(in: canvas)
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard isEditableLayout, let layout else { return }
        let screenRect = bounds.insetBy(dx: 16, dy: 22)
        for divider in dividerHits(for: layout, in: screenRect) {
            addCursorRect(divider.touchRect, cursor: divider.axis == .vertical ? .resizeLeftRight : .resizeUpDown)
        }
        addCursorRect(parkedDividerRect(axis: .horizontal, in: bounds.insetBy(dx: 8, dy: 8)).insetBy(dx: -6, dy: -6), cursor: .openHand)
        addCursorRect(parkedDividerRect(axis: .vertical, in: bounds.insetBy(dx: 8, dy: 8)).insetBy(dx: -6, dy: -6), cursor: .openHand)
    }

    // MARK: - Mouse Handling

    override func mouseDown(with event: NSEvent) {
        guard let layout else { return }
        let location = convert(event.locationInWindow, from: nil)
        let screenRect = bounds.insetBy(dx: 16, dy: 22)
        pendingSplitDrop = nil

        if isEditableLayout, let sourceAxis = parkedDividerAxis(at: location, in: bounds.insetBy(dx: 8, dy: 8)) {
            isDraggingSplitSource = true
            splitSourceAxis = sourceAxis
            splitSourceDragPoint = location
            needsDisplay = true
            return
        }

        activeDivider = dividerHits(for: layout, in: screenRect).first(where: { $0.touchRect.contains(location) })
        if let activeDivider {
            currentDividerRatio = nil
            selectedRegionIDs = activeDivider.regionIDs
            return
        }

        for region in layout.regions {
            let r = rect(for: region.normalizedFrame, in: screenRect)
            if r.contains(location) {
                selectedRegionIDs = [region.id]
                return
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let layout else { return }
        if isDraggingSplitSource {
            let current = convert(event.locationInWindow, from: nil)
            splitSourceDragPoint = current
            pendingSplitDrop = pendingSplitTarget(at: current, in: layout, axis: splitSourceAxis ?? .vertical)
            needsDisplay = true
            return
        }
        if let activeDivider {
            let screenRect = bounds.insetBy(dx: 16, dy: 22)
            let current = convert(event.locationInWindow, from: nil)
            let ratio: CGFloat
            switch activeDivider.axis {
            case .vertical:
                let value = max(activeDivider.ratioSpan.lowerBound, min(activeDivider.ratioSpan.upperBound, current.x))
                ratio = (value - activeDivider.ratioSpan.lowerBound) / max(1, activeDivider.ratioSpan.upperBound - activeDivider.ratioSpan.lowerBound)
            case .horizontal:
                let value = max(activeDivider.ratioSpan.lowerBound, min(activeDivider.ratioSpan.upperBound, current.y))
                ratio = (value - activeDivider.ratioSpan.lowerBound) / max(1, activeDivider.ratioSpan.upperBound - activeDivider.ratioSpan.lowerBound)
            }
            currentDividerRatio = ratio
            onDividerRatioChanged?(activeDivider.firstRegionIDs, activeDivider.secondRegionIDs, activeDivider.axis, ratio)
            self.activeDivider = dividerHits(for: layout, in: screenRect).first(where: { Set($0.regionIDs) == Set(selectedRegionIDs) })
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        if let activeDivider, let currentDividerRatio {
            onDividerInteractionEnded?(
                activeDivider.firstRegionIDs,
                activeDivider.secondRegionIDs,
                activeDivider.axis,
                currentDividerRatio
            )
        }
        if isDraggingSplitSource, let pendingSplitDrop {
            onSplitRequested?(pendingSplitDrop.regionID, pendingSplitDrop.axis, pendingSplitDrop.ratio)
        }
        isDraggingSplitSource = false
        splitSourceAxis = nil
        splitSourceDragPoint = nil
        pendingSplitDrop = nil
        currentDividerRatio = nil
        activeDivider = nil
        needsDisplay = true
    }

    // MARK: - Geometry

    private func rect(for normalizedFrame: CGRect, in screenRect: NSRect) -> NSRect {
        NSRect(
            x: screenRect.minX + (screenRect.width * normalizedFrame.minX),
            y: screenRect.minY + (screenRect.height * normalizedFrame.minY),
            width: screenRect.width * normalizedFrame.width,
            height: screenRect.height * normalizedFrame.height
        )
    }

    private func displayPercentageLabel(for frame: CGRect, axis: SplitAxis) -> String {
        let widthPercent = frame.width * 100
        let heightPercent = frame.height * 100
        return axis == .vertical
            ? String(format: "%.0f%%", widthPercent)
            : String(format: "%.0f%%", heightPercent)
    }

    private var splitSourceAxis: SplitAxis?

    // MARK: - Split Handles

    private func parkedDividerRect(axis: SplitAxis, in canvas: NSRect) -> NSRect {
        switch axis {
        case .horizontal:
            let y = canvas.maxY - 10
            return NSRect(x: canvas.midX - 10, y: y - 12, width: 20, height: 20)
        case .vertical:
            let x = canvas.minX + 10
            return NSRect(x: x - 10, y: canvas.midY - 10, width: 20, height: 20)
        }
    }

    private func drawParkedDividers(in canvas: NSRect) {
        drawParkedDivider(axis: .horizontal, in: canvas)
        drawParkedDivider(axis: .vertical, in: canvas)
    }

    private func drawParkedDivider(axis: SplitAxis, in canvas: NSRect) {
        let handleRect = parkedDividerRect(axis: axis, in: canvas)
        let bodyPath = NSBezierPath(roundedRect: handleRect, xRadius: 5, yRadius: 5)
        NSColor.windowBackgroundColor.withAlphaComponent(layoutOverlayControlAlpha).setFill()
        bodyPath.fill()
        NSColor.separatorColor.withAlphaComponent(layoutOverlayBorderAlpha).setStroke()
        bodyPath.lineWidth = 1
        bodyPath.stroke()

        let iconName = axis == .horizontal ? "arrow.down" : "arrow.right"
        if let icon = NSImage(systemSymbolName: iconName, accessibilityDescription: "Split Divider") {
            let iconRect = handleRect.insetBy(dx: 3, dy: 3)
            icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 0.62)
        }
    }

    private func parkedDividerAxis(at point: NSPoint, in canvas: NSRect) -> SplitAxis? {
        if parkedDividerRect(axis: .horizontal, in: canvas).insetBy(dx: -6, dy: -6).contains(point) { return .horizontal }
        if parkedDividerRect(axis: .vertical, in: canvas).insetBy(dx: -6, dy: -6).contains(point) { return .vertical }
        return nil
    }

    // While dragging, compute the prospective divider inside the hovered region so the
    // preview can show exactly where the split will land before the user releases.
    private func pendingSplitTarget(at point: NSPoint, in layout: RegionLayout, axis: SplitAxis) -> (regionID: Int, axis: SplitAxis, ratio: CGFloat, lineRect: NSRect)? {
        let screenRect = bounds.insetBy(dx: 16, dy: 22)
        for region in layout.regions {
            let regionRect = rect(for: region.normalizedFrame, in: screenRect)
            guard regionRect.contains(point) else { continue }
            switch axis {
            case .vertical:
                let ratio = (point.x - regionRect.minX) / max(1, regionRect.width)
                let clamped = max(0.05, min(0.95, ratio))
                let x = regionRect.minX + (regionRect.width * clamped)
                let lineRect = NSRect(x: x - 1, y: regionRect.minY, width: 2, height: regionRect.height)
                return (region.id, .vertical, clamped, lineRect)
            case .horizontal:
                let ratio = (point.y - regionRect.minY) / max(1, regionRect.height)
                let clamped = max(0.05, min(0.95, ratio))
                let y = regionRect.minY + (regionRect.height * clamped)
                let lineRect = NSRect(x: regionRect.minX, y: y - 1, width: regionRect.width, height: 2)
                return (region.id, .horizontal, clamped, lineRect)
            }
        }
        return nil
    }

    // Divider hits are derived from adjacent normalized regions rather than cached paths so
    // resizing, splitting, and merging always work from the current layout geometry.
    private func dividerHits(for layout: RegionLayout, in screenRect: NSRect) -> [DividerHit] {
        let epsilon: CGFloat = 0.001
        let touch: CGFloat = 12
        var results: [DividerHit] = []
        var seenKeys = Set<String>()

        let verticalBoundaries = uniqueBoundaries(
            layout.regions.flatMap { [$0.normalizedFrame.minX, $0.normalizedFrame.maxX] },
            excluding: [0, 1],
            epsilon: epsilon
        )
        for boundaryX in verticalBoundaries {
            let leftRegions = layout.regions.filter { abs($0.normalizedFrame.maxX - boundaryX) < epsilon }
            let rightRegions = layout.regions.filter { abs($0.normalizedFrame.minX - boundaryX) < epsilon }
            guard !leftRegions.isEmpty, !rightRegions.isEmpty else { continue }

            var minY = CGFloat.greatestFiniteMagnitude
            var maxY = -CGFloat.greatestFiniteMagnitude
            for left in leftRegions {
                for right in rightRegions {
                    let overlapMin = max(left.normalizedFrame.minY, right.normalizedFrame.minY)
                    let overlapMax = min(left.normalizedFrame.maxY, right.normalizedFrame.maxY)
                    guard overlapMax - overlapMin > epsilon else { continue }
                    minY = min(minY, overlapMin)
                    maxY = max(maxY, overlapMax)
                }
            }
            guard maxY > minY else { continue }

            let firstIDs = leftRegions.map(\.id).sorted()
            let secondIDs = rightRegions.map(\.id).sorted()
            let key = dividerKey(axis: .vertical, firstIDs: firstIDs, secondIDs: secondIDs)
            guard !seenKeys.contains(key) else { continue }
            seenKeys.insert(key)

            let x = screenRect.minX + (screenRect.width * boundaryX)
            let y = screenRect.minY + (screenRect.height * minY)
            let height = screenRect.height * (maxY - minY)
            guard height > 3 else { continue }
            let line = NSRect(x: x - 1, y: y, width: 2, height: height)
            let unionMinX = (leftRegions + rightRegions).map(\.normalizedFrame.minX).min() ?? 0
            let unionMaxX = (leftRegions + rightRegions).map(\.normalizedFrame.maxX).max() ?? 1
            let span = (screenRect.minX + (screenRect.width * unionMinX)) ... (screenRect.minX + (screenRect.width * unionMaxX))
            results.append(
                DividerHit(
                    firstRegionIDs: firstIDs,
                    secondRegionIDs: secondIDs,
                    axis: .vertical,
                    lineRect: line,
                    touchRect: line.insetBy(dx: -touch, dy: 0),
                    ratioSpan: span
                )
            )
        }

        let horizontalBoundaries = uniqueBoundaries(
            layout.regions.flatMap { [$0.normalizedFrame.minY, $0.normalizedFrame.maxY] },
            excluding: [0, 1],
            epsilon: epsilon
        )
        for boundaryY in horizontalBoundaries {
            let bottomRegions = layout.regions.filter { abs($0.normalizedFrame.maxY - boundaryY) < epsilon }
            let topRegions = layout.regions.filter { abs($0.normalizedFrame.minY - boundaryY) < epsilon }
            guard !bottomRegions.isEmpty, !topRegions.isEmpty else { continue }

            var minX = CGFloat.greatestFiniteMagnitude
            var maxX = -CGFloat.greatestFiniteMagnitude
            for bottom in bottomRegions {
                for top in topRegions {
                    let overlapMin = max(bottom.normalizedFrame.minX, top.normalizedFrame.minX)
                    let overlapMax = min(bottom.normalizedFrame.maxX, top.normalizedFrame.maxX)
                    guard overlapMax - overlapMin > epsilon else { continue }
                    minX = min(minX, overlapMin)
                    maxX = max(maxX, overlapMax)
                }
            }
            guard maxX > minX else { continue }

            let firstIDs = bottomRegions.map(\.id).sorted()
            let secondIDs = topRegions.map(\.id).sorted()
            let key = dividerKey(axis: .horizontal, firstIDs: firstIDs, secondIDs: secondIDs)
            guard !seenKeys.contains(key) else { continue }
            seenKeys.insert(key)

            let x = screenRect.minX + (screenRect.width * minX)
            let y = screenRect.minY + (screenRect.height * boundaryY)
            let width = screenRect.width * (maxX - minX)
            guard width > 3 else { continue }
            let line = NSRect(x: x, y: y - 1, width: width, height: 2)
            let unionMinY = (bottomRegions + topRegions).map(\.normalizedFrame.minY).min() ?? 0
            let unionMaxY = (bottomRegions + topRegions).map(\.normalizedFrame.maxY).max() ?? 1
            let span = (screenRect.minY + (screenRect.height * unionMinY)) ... (screenRect.minY + (screenRect.height * unionMaxY))
            results.append(
                DividerHit(
                    firstRegionIDs: firstIDs,
                    secondRegionIDs: secondIDs,
                    axis: .horizontal,
                    lineRect: line,
                    touchRect: line.insetBy(dx: 0, dy: -touch),
                    ratioSpan: span
                )
            )
        }
        return results
    }

    private func uniqueBoundaries(_ values: [CGFloat], excluding excluded: [CGFloat], epsilon: CGFloat) -> [CGFloat] {
        var result: [CGFloat] = []
        for value in values.sorted() {
            guard !excluded.contains(where: { abs($0 - value) < epsilon }) else { continue }
            guard !result.contains(where: { abs($0 - value) < epsilon }) else { continue }
            result.append(value)
        }
        return result
    }

    private func dividerKey(axis: SplitAxis, firstIDs: [Int], secondIDs: [Int]) -> String {
        let axisKey = axis == .vertical ? "v" : "h"
        return "\(axisKey):\(firstIDs.map(String.init).joined(separator: ","))|\(secondIDs.map(String.init).joined(separator: ","))"
    }
}

@MainActor
private final class DebugSettingsViewController: NSViewController {
    private let onDebugLoggingChanged: (Bool) -> Void

    private let checkbox = NSButton(checkboxWithTitle: "Enable debug logging", target: nil, action: nil)
    private let infoLabel = secondaryLabel("Write snap diagnostics to the PanePilot log file.")
    private let logLocationLabel = secondaryLabel()
    private let openLogsButton = NSButton(title: "Open Logs Folder", target: nil, action: nil)

    // MARK: - Initialization

    init(onDebugLoggingChanged: @escaping (Bool) -> Void) {
        self.onDebugLoggingChanged = onDebugLoggingChanged
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - View Lifecycle

    override func loadView() {
        view = NSView()
        configureUI()
        refreshState()
        preferredContentSize = settingsWindowContentSize
    }

    // MARK: - State

    func refreshState() {
        checkbox.state = DebugLogger.shared.isEnabled() ? .on : .off
        let logPath = NSString(string: DebugLogger.shared.logFileURL.path).abbreviatingWithTildeInPath
        logLocationLabel.stringValue = "Log file: \(logPath)"
    }

    // MARK: - Layout

    private func configureUI() {
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        checkbox.target = self
        checkbox.action = #selector(toggleLogging)

        openLogsButton.translatesAutoresizingMaskIntoConstraints = false
        openLogsButton.bezelStyle = .rounded
        openLogsButton.target = self
        openLogsButton.action = #selector(openLogs)

        view.addSubview(checkbox)
        view.addSubview(infoLabel)
        view.addSubview(logLocationLabel)
        view.addSubview(openLogsButton)

        NSLayoutConstraint.activate([
            checkbox.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            checkbox.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 80),

            infoLabel.topAnchor.constraint(equalTo: checkbox.bottomAnchor, constant: 8),
            infoLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 80),
            infoLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            logLocationLabel.topAnchor.constraint(equalTo: infoLabel.bottomAnchor, constant: 14),
            logLocationLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 80),
            logLocationLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            openLogsButton.topAnchor.constraint(equalTo: logLocationLabel.bottomAnchor, constant: 16),
            openLogsButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 80),
        ])
    }

    // MARK: - Actions

    @objc
    private func toggleLogging() {
        onDebugLoggingChanged(checkbox.state == .on)
    }

    @objc
    private func openLogs() {
        NSWorkspace.shared.activateFileViewerSelecting([DebugLogger.shared.logFileURL])
    }
}

@MainActor
private final class AboutSettingsViewController: NSViewController {
    // MARK: - View Lifecycle

    override func loadView() {
        view = NSView()
        configureUI()
        preferredContentSize = settingsWindowContentSize
    }

    // MARK: - Layout

    private func configureUI() {
        let container = NSStackView()
        container.orientation = .horizontal
        container.alignment = .top
        container.spacing = 14
        container.translatesAutoresizingMaskIntoConstraints = false

        let leftColumn = NSStackView()
        leftColumn.orientation = .horizontal
        leftColumn.alignment = .top
        leftColumn.spacing = 10
        leftColumn.translatesAutoresizingMaskIntoConstraints = false

        let iconView = NSImageView(image: AppIconProvider.iconImage(size: 50))
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleAxesIndependently
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 10

        let metaColumn = NSStackView()
        metaColumn.orientation = .vertical
        metaColumn.alignment = .leading
        metaColumn.spacing = 3

        let titleLabel = NSTextField(labelWithString: "PanePilot")
        titleLabel.font = NSFont.systemFont(ofSize: 21, weight: .semibold)

        let versionLabel = NSTextField(labelWithString: "Version \(applicationVersion)")
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)

        metaColumn.addArrangedSubview(titleLabel)
        metaColumn.addArrangedSubview(versionLabel)
        leftColumn.addArrangedSubview(iconView)
        leftColumn.addArrangedSubview(metaColumn)

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        let rightColumn = NSStackView()
        rightColumn.orientation = .vertical
        rightColumn.alignment = .leading
        rightColumn.spacing = 5

        let legalLabel = NSTextField(
            wrappingLabelWithString: """
            License: AGPL-3.0-only.
            Source and distributed binaries use the same license.
            """
        )
        legalLabel.textColor = .secondaryLabelColor
        legalLabel.alignment = .left
        legalLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        legalLabel.translatesAutoresizingMaskIntoConstraints = false

        let copyrightRow = NSStackView()
        copyrightRow.orientation = .horizontal
        copyrightRow.alignment = .firstBaseline
        copyrightRow.spacing = 3

        let copyrightLabel = NSTextField(labelWithString: "Copyright © 2026")
        copyrightLabel.textColor = .secondaryLabelColor
        copyrightLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)

        let profileButton = makeLinkButton(title: "Joakim Persson", url: "https://github.com/hansjoakimpersson")
        let websiteButton = makeLinkButton(title: "PanePilot website", url: "https://hansjoakimpersson.github.io/PanePilot/")

        copyrightRow.addArrangedSubview(copyrightLabel)
        copyrightRow.addArrangedSubview(profileButton)

        rightColumn.addArrangedSubview(legalLabel)
        rightColumn.addArrangedSubview(copyrightRow)
        rightColumn.addArrangedSubview(websiteButton)

        container.addArrangedSubview(leftColumn)
        container.addArrangedSubview(divider)
        container.addArrangedSubview(rightColumn)

        view.addSubview(container)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 50),
            iconView.heightAnchor.constraint(equalToConstant: 50),
            divider.heightAnchor.constraint(equalToConstant: 96),
            leftColumn.widthAnchor.constraint(equalToConstant: 156),
            legalLabel.widthAnchor.constraint(equalToConstant: 200),
            container.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            container.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        ])
    }

    private func makeLinkButton(title: String, url: String) -> NSButton {
        let button = NSButton(title: title, target: self, action: #selector(openLink(_:)))
        button.bezelStyle = .inline
        button.isBordered = false
        button.alignment = .left
        button.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        button.contentTintColor = .linkColor
        button.toolTip = url
        button.setAccessibilityLabel(title)
        button.identifier = NSUserInterfaceItemIdentifier(url)
        return button
    }

    @objc
    private func openLink(_ sender: NSButton) {
        guard let rawValue = sender.identifier?.rawValue,
              let url = URL(string: rawValue) else { return }
        NSWorkspace.shared.open(url)
    }

    private var applicationVersion: String {
        let base = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? Bundle.main.infoDictionary?["CFBundleVersion"] as? String
            ?? "dev"
        #if DEBUG
        return "\(base) (dev)"
        #else
        return base
        #endif
    }
}

private final class SettingsTabViewController: NSTabViewController {
    var onSelectionChanged: (() -> Void)?

    override var preferredContentSize: NSSize {
        get { settingsWindowContentSize }
        set { super.preferredContentSize = settingsWindowContentSize }
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        preferredContentSize = settingsWindowContentSize
    }

    // MARK: - NSTabViewController

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        preferredContentSize = settingsWindowContentSize
        onSelectionChanged?()
    }
}
