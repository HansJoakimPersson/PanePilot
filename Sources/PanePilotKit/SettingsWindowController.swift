import AppKit
import Foundation

private let settingsBuiltInLayoutOrder = [
    RegionLayouts.split20x80.id,
    RegionLayouts.split80x20.id,
    RegionLayouts.threeColumn.id,
]

private func orderedSettingsLayouts(_ source: [RegionLayout]) -> [RegionLayout] {
    let builtIns = settingsBuiltInLayoutOrder.compactMap { id in source.first(where: { $0.id == id }) }
    let custom = source
        .filter { !settingsBuiltInLayoutOrder.contains($0.id) }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    return builtIns + custom
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    var onWindowClosed: (() -> Void)?

    private let tabController = SettingsTabViewController()
    private let generalViewController: GeneralSettingsViewController
    private let layoutsViewController: LayoutsSettingsViewController
    private let displaysViewController: DisplaysSettingsViewController
    private let debugViewController: DebugSettingsViewController
    private let aboutViewController = AboutSettingsViewController()

    // MARK: - Initialization

    init(
        store: DisplayLayoutStore,
        initialSnapModifier: SnapModifier,
        onSnapModifierChanged: @escaping (SnapModifier) -> Void,
        onDebugLoggingChanged: @escaping (Bool) -> Void
    ) {
        self.generalViewController = GeneralSettingsViewController(
            initialSnapModifier: initialSnapModifier,
            onSnapModifierChanged: onSnapModifierChanged
        )
        self.layoutsViewController = LayoutsSettingsViewController(store: store)
        self.displaysViewController = DisplaysSettingsViewController(store: store)
        self.debugViewController = DebugSettingsViewController(onDebugLoggingChanged: onDebugLoggingChanged)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 430),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        super.init(window: window)

        configureWindow(window)
        configureTabs()
        wireEvents()

        window.contentViewController = tabController
        window.delegate = self
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
        window.contentMinSize = NSSize(width: 450, height: 430)
        window.contentMaxSize = NSSize(width: 450, height: 430)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
    }

    private func refreshContent() {
        generalViewController.refreshFromSystem()
        layoutsViewController.reloadLayouts(selectLayoutID: nil)
        displaysViewController.reloadAll(selectDisplayID: nil)
        debugViewController.refreshState()
    }

    private func configureTabs() {
        tabController.tabStyle = .toolbar
        tabController.onSelectionChanged = { [weak self] in
            self?.updateWindowTitle()
        }

        tabController.addTabViewItem(
            makeTabItem(label: "General", symbolName: "gearshape", accessibilityDescription: "General", viewController: generalViewController)
        )
        tabController.addTabViewItem(
            makeTabItem(label: "Layouts", symbolName: "rectangle.split.3x1", accessibilityDescription: "Layouts", viewController: layoutsViewController)
        )
        tabController.addTabViewItem(
            makeTabItem(label: "Displays", symbolName: "display", accessibilityDescription: "Displays", viewController: displaysViewController)
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
            self?.displaysViewController.reloadAll(selectDisplayID: nil)
            self?.layoutsViewController.reloadLayouts(selectLayoutID: selectedID)
        }
    }

    private func updateWindowTitle() {
        window?.title = tabController.tabView.selectedTabViewItem?.label ?? "Settings"
    }
}

@MainActor
private final class GeneralSettingsViewController: NSViewController {
    private let onSnapModifierChanged: (SnapModifier) -> Void

    private let startAtLoginCheckbox = NSButton(checkboxWithTitle: "Start at Login", target: nil, action: nil)
    private let startAtLoginInfoLabel = NSTextField(wrappingLabelWithString: "Automatically opens the app when you start your Mac.")
    private let shortcutLabel = NSTextField(labelWithString: "Snap Modifier")
    private let shortcutPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let shortcutInfoLabel = NSTextField(wrappingLabelWithString: "Hold this key while dragging to activate snap regions.")
    private let accessibilityLabel = NSTextField(labelWithString: "")
    private let accessibilityButton = NSButton(title: "", target: nil, action: nil)

    // MARK: - Initialization

    init(initialSnapModifier: SnapModifier, onSnapModifierChanged: @escaping (SnapModifier) -> Void) {
        self.onSnapModifierChanged = onSnapModifierChanged
        super.init(nibName: nil, bundle: nil)

        shortcutPopup.addItems(withTitles: SnapModifier.allCases.map(\.displayName))
        if let idx = SnapModifier.allCases.firstIndex(of: initialSnapModifier) {
            shortcutPopup.selectItem(at: idx)
        } else if let idx = SnapModifier.allCases.firstIndex(of: .command) {
            shortcutPopup.selectItem(at: idx)
        }
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
    }

    // MARK: - State

    func refreshFromSystem() {
        let available = LoginItemManager.shared.isFeatureAvailable
        startAtLoginCheckbox.isEnabled = available
        startAtLoginCheckbox.state = LoginItemManager.shared.isEnabled() ? .on : .off
        startAtLoginCheckbox.toolTip = available ? nil : LoginItemManager.shared.unavailableReason
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

        shortcutLabel.translatesAutoresizingMaskIntoConstraints = false

        shortcutPopup.translatesAutoresizingMaskIntoConstraints = false
        shortcutPopup.target = self
        shortcutPopup.action = #selector(shortcutChanged)

        shortcutInfoLabel.translatesAutoresizingMaskIntoConstraints = false
        shortcutInfoLabel.textColor = .secondaryLabelColor
        shortcutInfoLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)

        accessibilityLabel.translatesAutoresizingMaskIntoConstraints = false
        accessibilityLabel.textColor = .secondaryLabelColor
        accessibilityLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)

        accessibilityButton.translatesAutoresizingMaskIntoConstraints = false
        accessibilityButton.bezelStyle = .rounded
        accessibilityButton.target = self
        accessibilityButton.action = #selector(enableAccessibility)

        view.addSubview(startAtLoginCheckbox)
        view.addSubview(startAtLoginInfoLabel)
        view.addSubview(shortcutLabel)
        view.addSubview(shortcutPopup)
        view.addSubview(shortcutInfoLabel)
        view.addSubview(accessibilityLabel)
        view.addSubview(accessibilityButton)

        NSLayoutConstraint.activate([
            startAtLoginCheckbox.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            startAtLoginCheckbox.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 80),

            startAtLoginInfoLabel.topAnchor.constraint(equalTo: startAtLoginCheckbox.bottomAnchor, constant: 8),
            startAtLoginInfoLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 80),
            startAtLoginInfoLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            shortcutLabel.topAnchor.constraint(equalTo: startAtLoginInfoLabel.bottomAnchor, constant: 20),
            shortcutLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 80),
            shortcutLabel.centerYAnchor.constraint(equalTo: shortcutPopup.centerYAnchor),

            shortcutPopup.topAnchor.constraint(equalTo: startAtLoginInfoLabel.bottomAnchor, constant: 20),
            shortcutPopup.leadingAnchor.constraint(equalTo: shortcutLabel.trailingAnchor, constant: 12),
            shortcutPopup.widthAnchor.constraint(equalToConstant: 190),

            shortcutInfoLabel.topAnchor.constraint(equalTo: shortcutPopup.bottomAnchor, constant: 8),
            shortcutInfoLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 80),
            shortcutInfoLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            accessibilityLabel.topAnchor.constraint(equalTo: shortcutInfoLabel.bottomAnchor, constant: 20),
            accessibilityLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 80),
            accessibilityLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            accessibilityButton.topAnchor.constraint(equalTo: accessibilityLabel.bottomAnchor, constant: 8),
            accessibilityButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 80),
        ])
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

    @objc
    private func shortcutChanged() {
        let idx = shortcutPopup.indexOfSelectedItem
        guard idx >= 0, idx < SnapModifier.allCases.count else { return }
        onSnapModifierChanged(SnapModifier.allCases[idx])
    }

    @objc
    private func enableAccessibility() {
        _ = PermissionManager().ensureAccessibilityPermission(prompt: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.updateAccessibilityStatus()
        }
    }

    // macOS does not update the permission state synchronously when opening System Settings,
    // so the settings screen re-checks the flag after a short delay.
    private func updateAccessibilityStatus() {
        let enabled = PermissionManager().ensureAccessibilityPermission(prompt: false)
        if enabled {
            accessibilityLabel.stringValue = "Accessibility: Enabled"
            accessibilityButton.title = "Accessibility Enabled"
            accessibilityButton.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Enabled")
            accessibilityButton.isEnabled = false
        } else {
            accessibilityLabel.stringValue = "Accessibility: Not Enabled"
            accessibilityButton.title = "Enable Accessibility"
            accessibilityButton.image = NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: "Enable")
            accessibilityButton.isEnabled = true
        }
    }
}

@MainActor
private final class LayoutsSettingsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    var onLayoutsChanged: ((String?) -> Void)?

    private let store: DisplayLayoutStore
    private var layouts: [RegionLayout] = []

    private let tableView = NSTableView(frame: .zero)
    private let scrollView = NSScrollView(frame: .zero)
    private let addButton = NSButton(title: "+", target: nil, action: nil)
    private let removeButton = NSButton(title: "-", target: nil, action: nil)
    private let previewView = LayoutPreviewView(frame: .zero)
    private let dividerHandleBadge = NSImageView(frame: .zero)
    private let mergeHandleButton = NSButton(title: "", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private var isSynchronizingPreviewState = false
    private var dividerHandleCenterX: NSLayoutConstraint?
    private var dividerHandleCenterY: NSLayoutConstraint?
    private var mergeHandleCenterX: NSLayoutConstraint?
    private var mergeHandleCenterY: NSLayoutConstraint?
    private var activeLayoutIDForInteractiveResize: String?

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
    }

    // MARK: - Data Loading

    func reloadLayouts(selectLayoutID: String?) {
        layouts = orderedSettingsLayouts(store.allLayouts())
        tableView.reloadData()

        if let selectLayoutID,
           let idx = layouts.firstIndex(where: { $0.id == selectLayoutID }) {
            tableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
        } else if tableView.selectedRow < 0, !layouts.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }

        updateEditorForSelection()
    }

    // MARK: - Layout

    private func configureUI() {
        let colName = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        colName.title = "Layouts"
        colName.width = 110
        tableView.addTableColumn(colName)

        let colType = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("type"))
        colType.title = "Type"
        colType.width = 80
        tableView.addTableColumn(colType)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.target = self
        tableView.doubleAction = #selector(handleTableDoubleClick)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.wantsLayer = true
        scrollView.layer?.cornerRadius = 8
        scrollView.layer?.masksToBounds = true
        scrollView.borderType = .bezelBorder

        addButton.bezelStyle = .rounded
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.target = self
        addButton.action = #selector(addLayout)

        removeButton.bezelStyle = .rounded
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        removeButton.target = self
        removeButton.action = #selector(removeLayout)

        previewView.translatesAutoresizingMaskIntoConstraints = false
        previewView.wantsLayer = true
        previewView.onSelectionChanged = { [weak self] _ in
            guard let self, !self.isSynchronizingPreviewState else { return }
            self.updateEditorForSelection()
        }
        previewView.onDragSelectionChanged = { [weak self] _ in
            guard let self, !self.isSynchronizingPreviewState else { return }
            self.updateEditorForSelection()
        }
        previewView.onDividerRatioChanged = { [weak self] firstRegionID, secondRegionID, ratio in
            self?.handleDividerRatioChanged(firstRegionID: firstRegionID, secondRegionID: secondRegionID, ratio: ratio)
        }
        previewView.onSplitRequested = { [weak self] regionID, axis, ratio in
            self?.handleSplitRequested(regionID: regionID, axis: axis, ratio: ratio)
        }

        dividerHandleBadge.translatesAutoresizingMaskIntoConstraints = false
        dividerHandleBadge.image = NSImage(systemSymbolName: "arrow.left.and.right.square", accessibilityDescription: "Resize Divider")
        dividerHandleBadge.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        dividerHandleBadge.wantsLayer = true
        dividerHandleBadge.layer?.cornerRadius = 6
        dividerHandleBadge.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92).cgColor
        dividerHandleBadge.layer?.borderWidth = 1
        dividerHandleBadge.layer?.borderColor = NSColor.separatorColor.cgColor
        dividerHandleBadge.isHidden = true

        mergeHandleButton.translatesAutoresizingMaskIntoConstraints = false
        mergeHandleButton.bezelStyle = .texturedRounded
        mergeHandleButton.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: "Remove Divider")
        mergeHandleButton.isBordered = true
        mergeHandleButton.target = self
        mergeHandleButton.action = #selector(mergeSelectedRegions)
        mergeHandleButton.isHidden = true

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)

        view.addSubview(scrollView)
        view.addSubview(addButton)
        view.addSubview(removeButton)
        view.addSubview(previewView)
        view.addSubview(dividerHandleBadge)
        view.addSubview(mergeHandleButton)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            scrollView.widthAnchor.constraint(equalToConstant: 170),
            scrollView.bottomAnchor.constraint(equalTo: addButton.topAnchor, constant: -10),

            addButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            addButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            addButton.widthAnchor.constraint(equalToConstant: 30),

            removeButton.leadingAnchor.constraint(equalTo: addButton.trailingAnchor, constant: 8),
            removeButton.centerYAnchor.constraint(equalTo: addButton.centerYAnchor),
            removeButton.widthAnchor.constraint(equalToConstant: 30),

            previewView.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            previewView.leadingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: 14),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            previewView.heightAnchor.constraint(equalToConstant: 160),

            dividerHandleBadge.widthAnchor.constraint(equalToConstant: 22),
            dividerHandleBadge.heightAnchor.constraint(equalToConstant: 22),
            mergeHandleButton.widthAnchor.constraint(equalToConstant: 22),
            mergeHandleButton.heightAnchor.constraint(equalToConstant: 22),
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

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int { layouts.count }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < layouts.count else { return nil }
        let layout = layouts[row]
        if tableColumn?.identifier.rawValue == "type" {
            let cellID = NSUserInterfaceItemIdentifier("LayoutTypeCell")
            let cell = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView ?? {
                let c = NSTableCellView()
                c.identifier = cellID
                let label = NSTextField(labelWithString: "")
                label.translatesAutoresizingMaskIntoConstraints = false
                label.textColor = .secondaryLabelColor
                c.addSubview(label)
                c.textField = label
                NSLayoutConstraint.activate([
                    label.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 6),
                    label.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -6),
                    label.centerYAnchor.constraint(equalTo: c.centerYAnchor),
                ])
                return c
            }()
            cell.textField?.stringValue = store.isLayoutEditable(id: layout.id) ? "Custom" : "Built-in"
            return cell
        }

        let cellID = NSUserInterfaceItemIdentifier("LayoutNameCell")
        let cell = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView ?? {
            let c = NSTableCellView()
            c.identifier = cellID
            let field = NSTextField(string: "")
            field.translatesAutoresizingMaskIntoConstraints = false
            field.isBordered = false
            field.drawsBackground = false
            field.focusRingType = .none
            field.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            c.addSubview(field)
            c.textField = field
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 6),
                field.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -6),
                field.centerYAnchor.constraint(equalTo: c.centerYAnchor),
            ])
            return c
        }()

        cell.textField?.stringValue = layout.name
        cell.textField?.isEditable = store.isLayoutEditable(id: layout.id)
        cell.textField?.isSelectable = true
        cell.textField?.delegate = self
        cell.textField?.tag = row
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) { updateEditorForSelection() }

    // MARK: - Actions

    @objc
    private func addLayout() {
        let layout = store.addFullscreenLayout(name: "")
        reloadLayouts(selectLayoutID: layout.id)
        onLayoutsChanged?(layout.id)
    }

    @objc
    private func removeLayout() {
        let row = tableView.selectedRow
        guard row >= 0, row < layouts.count else { return }
        let layout = layouts[row]
        guard store.isLayoutEditable(id: layout.id) else { return }
        if store.removeLayout(id: layout.id) {
            reloadLayouts(selectLayoutID: nil)
            onLayoutsChanged?(nil)
        }
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
        guard row >= 0, row < layouts.count else { return nil }
        return layouts[row]
    }

    // MARK: - Preview Synchronization

    private func updateEditorForSelection() {
        guard let layout = selectedLayout else {
            synchronizePreviewState {
                previewView.layout = nil
            }
            removeButton.isEnabled = false
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
        previewView.isEditableLayout = editable
        updateDividerHandle(for: layout, canEdit: editable)

        if let regionID = previewView.primarySelectedRegionID,
           let region = layout.regions.first(where: { $0.id == regionID }) {
            let percent = max(region.normalizedFrame.width, region.normalizedFrame.height) * 100.0
            updateMergeHandle(for: layout, canEdit: editable)
            if previewView.selectedRegionIDs.count == 2 {
                statusLabel.stringValue = mergeHandleButton.isEnabled ? "Merge handle available on divider." : "Selected regions are not mergeable."
            } else if editable {
                statusLabel.stringValue = "Drag top divider for horizontal split or left divider for vertical split."
            } else {
                statusLabel.stringValue = "Selected region: \(Int(round(percent)))%"
            }
        } else {
            updateMergeHandle(for: layout, canEdit: editable)
            statusLabel.stringValue = "Select a region in the preview."
        }
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

    private func handleDividerRatioChanged(firstRegionID: Int, secondRegionID: Int, ratio: CGFloat) {
        guard let layout = selectedLayout else { return }
        activeLayoutIDForInteractiveResize = layout.id
        guard let updated = store.resizeAdjacentRegions(
            layoutID: layout.id,
            firstRegionID: firstRegionID,
            secondRegionID: secondRegionID,
            ratio: ratio
        ) else { return }
        if let index = layouts.firstIndex(where: { $0.id == updated.id }) {
            layouts[index] = updated
        }
        synchronizePreviewState {
            previewView.layout = updated
        }
        updateEditorForSelection()
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
            mergePoint = CGPoint(x: point.x, y: point.y + 16)
        case .horizontal:
            mergePoint = CGPoint(x: point.x - 16, y: point.y)
        }

        let yFromTop = max(0, previewView.bounds.height - mergePoint.y)
        mergeHandleCenterX?.constant = mergePoint.x
        mergeHandleCenterY?.constant = yFromTop
        mergeHandleButton.isHidden = false
        mergeHandleButton.isEnabled = true
    }

    private func updateDividerHandle(for layout: RegionLayout, canEdit: Bool) {
        guard canEdit,
              previewView.selectedRegionIDs.count == 2,
              let point = previewView.selectedDividerPoint(),
              let axis = previewView.selectedDividerAxis() else {
            dividerHandleBadge.isHidden = true
            return
        }

        dividerHandleBadge.image = NSImage(
            systemSymbolName: axis == .vertical ? "arrow.left.and.right.square" : "arrow.up.and.down.square",
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
        let column = tableView.clickedColumn
        guard row >= 0, row < layouts.count else { return }
        guard column == 0 else { return }
        let layout = layouts[row]
        guard store.isLayoutEditable(id: layout.id) else { return }
        tableView.editColumn(0, row: row, with: nil, select: true)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField else { return }
        let row = textField.tag
        guard row >= 0, row < layouts.count else { return }

        let layout = layouts[row]
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
        let firstRegionID: Int
        let secondRegionID: Int
        let axis: SplitAxis
        let lineRect: NSRect
        let touchRect: NSRect
        let ratioSpan: ClosedRange<CGFloat>
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
    var onDividerRatioChanged: ((Int, Int, CGFloat) -> Void)?
    var onSplitRequested: ((Int, SplitAxis, CGFloat) -> Void)?
    var isEditableLayout: Bool = false
    private var dragStartPoint: NSPoint?
    private var activeDivider: DividerHit?
    private var isDraggingSplitSource = false
    private var splitSourceDragPoint: NSPoint?
    private var pendingSplitDrop: (regionID: Int, axis: SplitAxis, ratio: CGFloat, lineRect: NSRect)?

    // MARK: - Selection Helpers

    func selectedDividerPoint() -> CGPoint? {
        guard let layout, selectedRegionIDs.count == 2 else { return nil }
        guard let first = layout.regions.first(where: { $0.id == selectedRegionIDs[0] }),
              let second = layout.regions.first(where: { $0.id == selectedRegionIDs[1] }) else { return nil }

        let screenRect = bounds.insetBy(dx: 16, dy: 22)
        let firstRect = rect(for: first.normalizedFrame, in: screenRect)
        let secondRect = rect(for: second.normalizedFrame, in: screenRect)
        let epsilon: CGFloat = 1.0

        if abs(firstRect.maxX - secondRect.minX) < epsilon || abs(secondRect.maxX - firstRect.minX) < epsilon {
            let x = abs(firstRect.maxX - secondRect.minX) < epsilon ? firstRect.maxX : secondRect.maxX
            let overlapMinY = max(firstRect.minY, secondRect.minY)
            let overlapMaxY = min(firstRect.maxY, secondRect.maxY)
            guard overlapMaxY > overlapMinY else { return nil }
            return CGPoint(x: x, y: (overlapMinY + overlapMaxY) / 2)
        }

        if abs(firstRect.maxY - secondRect.minY) < epsilon || abs(secondRect.maxY - firstRect.minY) < epsilon {
            let y = abs(firstRect.maxY - secondRect.minY) < epsilon ? firstRect.maxY : secondRect.maxY
            let overlapMinX = max(firstRect.minX, secondRect.minX)
            let overlapMaxX = min(firstRect.maxX, secondRect.maxX)
            guard overlapMaxX > overlapMinX else { return nil }
            return CGPoint(x: (overlapMinX + overlapMaxX) / 2, y: y)
        }

        return nil
    }

    func selectedDividerAxis() -> SplitAxis? {
        guard let layout else { return nil }
        return dividerHits(for: layout, in: bounds.insetBy(dx: 16, dy: 22))
            .first(where: { Set([$0.firstRegionID, $0.secondRegionID]) == Set(selectedRegionIDs) })?
            .axis
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let canvas = bounds.insetBy(dx: 8, dy: 8)
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(rect: canvas).fill()

        let screenRect = canvas.insetBy(dx: 8, dy: 14)
        let path = NSBezierPath(roundedRect: screenRect, xRadius: 8, yRadius: 8)
        NSColor.controlAccentColor.withAlphaComponent(0.08).setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()

        if isEditableLayout {
            drawParkedDividers(in: canvas)
        }

        guard let layout else { return }
        let dividers = dividerHits(for: layout, in: screenRect)
        for region in layout.regions {
            let r = rect(for: region.normalizedFrame, in: screenRect).insetBy(dx: 1, dy: 1)

            let regionPath = NSBezierPath(roundedRect: r, xRadius: 5, yRadius: 5)
            if selectedRegionIDs.contains(region.id) {
                NSColor.systemBlue.withAlphaComponent(0.35).setFill()
            } else {
                NSColor.systemGray.withAlphaComponent(0.2).setFill()
            }
            regionPath.fill()
            NSColor.separatorColor.setStroke()
            regionPath.lineWidth = 1
            regionPath.stroke()

            if let activeDivider,
               (region.id == activeDivider.firstRegionID || region.id == activeDivider.secondRegionID) {
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
            NSColor.controlAccentColor.withAlphaComponent(0.35).setFill()
            NSBezierPath(roundedRect: activeDivider.lineRect.insetBy(dx: -2, dy: -2), xRadius: 4, yRadius: 4).fill()
        } else if selectedRegionIDs.count == 2,
                  let divider = dividers.first(where: { Set([$0.firstRegionID, $0.secondRegionID]) == Set(selectedRegionIDs) }) {
            NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
            NSBezierPath(roundedRect: divider.lineRect.insetBy(dx: -1, dy: -1), xRadius: 4, yRadius: 4).fill()
        }

        if let pendingSplitDrop {
            NSColor.controlAccentColor.withAlphaComponent(0.28).setFill()
            NSBezierPath(roundedRect: pendingSplitDrop.lineRect.insetBy(dx: -2, dy: -2), xRadius: 4, yRadius: 4).fill()
        }
    }

    // MARK: - Mouse Handling

    override func mouseDown(with event: NSEvent) {
        guard let layout else { return }
        let location = convert(event.locationInWindow, from: nil)
        let screenRect = bounds.insetBy(dx: 16, dy: 22)
        let isAdditiveSelection = event.modifierFlags.contains(.command)
        dragStartPoint = location
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
            selectedRegionIDs = [activeDivider.firstRegionID, activeDivider.secondRegionID]
            return
        }

        for region in layout.regions {
            let r = rect(for: region.normalizedFrame, in: screenRect)
            if r.contains(location) {
                if isAdditiveSelection {
                    if let existingIndex = selectedRegionIDs.firstIndex(of: region.id) {
                        selectedRegionIDs.remove(at: existingIndex)
                    } else {
                        selectedRegionIDs.append(region.id)
                        if selectedRegionIDs.count > 2 {
                            selectedRegionIDs.removeFirst(selectedRegionIDs.count - 2)
                        }
                    }
                    if selectedRegionIDs.isEmpty {
                        selectedRegionIDs = [region.id]
                    }
                } else {
                    selectedRegionIDs = [region.id]
                }
                return
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let layout, let dragStartPoint else { return }
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
            onDividerRatioChanged?(activeDivider.firstRegionID, activeDivider.secondRegionID, ratio)
            self.activeDivider = dividerHits(for: layout, in: screenRect).first(where: { Set([$0.firstRegionID, $0.secondRegionID]) == Set(selectedRegionIDs) })
            needsDisplay = true
            return
        }
        let current = convert(event.locationInWindow, from: nil)
        let selectionRect = NSRect(
            x: min(dragStartPoint.x, current.x),
            y: min(dragStartPoint.y, current.y),
            width: abs(current.x - dragStartPoint.x),
            height: abs(current.y - dragStartPoint.y)
        )
        guard selectionRect.width > 6 || selectionRect.height > 6 else { return }

        let screenRect = bounds.insetBy(dx: 16, dy: 22)
        let selected = layout.regions.compactMap { region -> (Int, CGFloat)? in
            let regionRect = rect(for: region.normalizedFrame, in: screenRect)
            let intersection = selectionRect.intersection(regionRect)
            guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else { return nil }
            return (region.id, intersection.width * intersection.height)
        }
            .sorted { $0.1 > $1.1 }
            .map(\.0)

        let topTwo = Array(selected.prefix(2))
        if !topTwo.isEmpty, topTwo != selectedRegionIDs {
            selectedRegionIDs = topTwo
            onDragSelectionChanged?(topTwo)
        }
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        if isDraggingSplitSource, let pendingSplitDrop {
            onSplitRequested?(pendingSplitDrop.regionID, pendingSplitDrop.axis, pendingSplitDrop.ratio)
        }
        isDraggingSplitSource = false
        splitSourceAxis = nil
        splitSourceDragPoint = nil
        pendingSplitDrop = nil
        dragStartPoint = nil
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
        let widthPercent = Int(round(frame.width * 100))
        let heightPercent = Int(round(frame.height * 100))
        return axis == .vertical ? "\(widthPercent)%" : "\(heightPercent)%"
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
        NSColor.windowBackgroundColor.withAlphaComponent(0.9).setFill()
        bodyPath.fill()
        NSColor.separatorColor.setStroke()
        bodyPath.lineWidth = 1
        bodyPath.stroke()

        let iconName = axis == .horizontal ? "arrow.down" : "arrow.right"
        if let icon = NSImage(systemSymbolName: iconName, accessibilityDescription: "Split Divider") {
            let iconRect = handleRect.insetBy(dx: 3, dy: 3)
            icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 0.85)
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
        let touch: CGFloat = 8
        var results: [DividerHit] = []

        for i in 0 ..< layout.regions.count {
            for j in (i + 1) ..< layout.regions.count {
                let a = layout.regions[i]
                let b = layout.regions[j]
                let af = a.normalizedFrame
                let bf = b.normalizedFrame

                let sameMinY = abs(af.minY - bf.minY) < epsilon
                let sameHeight = abs(af.height - bf.height) < epsilon
                let sideBySide = abs(af.maxX - bf.minX) < epsilon || abs(bf.maxX - af.minX) < epsilon
                if sameMinY && sameHeight && sideBySide {
                    let aRect = rect(for: af, in: screenRect)
                    let bRect = rect(for: bf, in: screenRect)
                    let leftIsA = af.minX < bf.minX
                    let leftRect = leftIsA ? aRect : bRect
                    let rightRect = leftIsA ? bRect : aRect
                    let x = leftRect.maxX
                    let line = NSRect(x: x - 1, y: max(leftRect.minY, rightRect.minY), width: 2, height: min(leftRect.maxY, rightRect.maxY) - max(leftRect.minY, rightRect.minY))
                    guard line.height > 3 else { continue }
                    let touchRect = line.insetBy(dx: -touch, dy: 0)
                    let span = leftRect.minX ... rightRect.maxX
                    results.append(
                        DividerHit(
                            firstRegionID: leftIsA ? a.id : b.id,
                            secondRegionID: leftIsA ? b.id : a.id,
                            axis: .vertical,
                            lineRect: line,
                            touchRect: touchRect,
                            ratioSpan: span
                        )
                    )
                    continue
                }

                let sameMinX = abs(af.minX - bf.minX) < epsilon
                let sameWidth = abs(af.width - bf.width) < epsilon
                let stacked = abs(af.maxY - bf.minY) < epsilon || abs(bf.maxY - af.minY) < epsilon
                if sameMinX && sameWidth && stacked {
                    let aRect = rect(for: af, in: screenRect)
                    let bRect = rect(for: bf, in: screenRect)
                    let bottomIsA = af.minY < bf.minY
                    let bottomRect = bottomIsA ? aRect : bRect
                    let topRect = bottomIsA ? bRect : aRect
                    let y = bottomRect.maxY
                    let line = NSRect(x: max(bottomRect.minX, topRect.minX), y: y - 1, width: min(bottomRect.maxX, topRect.maxX) - max(bottomRect.minX, topRect.minX), height: 2)
                    guard line.width > 3 else { continue }
                    let touchRect = line.insetBy(dx: 0, dy: -touch)
                    let span = bottomRect.minY ... topRect.maxY
                    results.append(
                        DividerHit(
                            firstRegionID: bottomIsA ? a.id : b.id,
                            secondRegionID: bottomIsA ? b.id : a.id,
                            axis: .horizontal,
                            lineRect: line,
                            touchRect: touchRect,
                            ratioSpan: span
                        )
                    )
                }
            }
        }
        return results
    }
}

@MainActor
private final class DisplaysSettingsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let store: DisplayLayoutStore
    private var records: [DisplayRecord] = []
    private var layouts: [RegionLayout] = []
    private let maxDisplayedRows = 4

    private let tableView = NSTableView(frame: .zero)
    private let scrollView = NSScrollView(frame: .zero)

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
        reloadAll(selectDisplayID: nil)
    }

    // MARK: - Data Loading

    func reloadAll(selectDisplayID: String?) {
        store.refreshConnectedDisplays()
        records = trimmedRecords(store.allRecords())
        layouts = orderedSettingsLayouts(store.allLayouts())
        tableView.reloadData()

        if let selectDisplayID,
           let idx = records.firstIndex(where: { $0.displayID == selectDisplayID }) {
            tableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
        }
    }

    private func trimmedRecords(_ source: [DisplayRecord]) -> [DisplayRecord] {
        Array(source.prefix(maxDisplayedRows))
    }

    // MARK: - Layout

    private func configureUI() {
        let colDisplay = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("display"))
        colDisplay.title = "Display"
        colDisplay.width = 190
        tableView.addTableColumn(colDisplay)

        let colStatus = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("status"))
        colStatus.title = "Status"
        colStatus.width = 90
        tableView.addTableColumn(colStatus)

        let colLayout = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("layout"))
        colLayout.title = "Layout"
        colLayout.width = 150
        tableView.addTableColumn(colLayout)

        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowHeight = 22

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
        ])
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int { records.count }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < records.count else { return nil }
        let record = records[row]

        switch tableColumn?.identifier.rawValue {
        case "layout":
            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            popup.addItems(withTitles: layouts.map(\.name))
            if let idx = layouts.firstIndex(where: { $0.id == record.layoutID }) {
                popup.selectItem(at: idx)
            }
            popup.tag = row
            popup.target = self
            popup.action = #selector(layoutSelectionChanged(_:))

            let wrapper = NSTableCellView()
            popup.translatesAutoresizingMaskIntoConstraints = false
            wrapper.addSubview(popup)
            NSLayoutConstraint.activate([
                popup.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 4),
                popup.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -4),
                popup.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 2),
                popup.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -2),
            ])
            return wrapper

        case "display", "status":
            let text: String = tableColumn?.identifier.rawValue == "display"
                ? record.name
                : (record.isConnected ? "Connected" : "Offline")

            let cellID = NSUserInterfaceItemIdentifier("DisplayTextCell")
            let cell = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView ?? {
                let c = NSTableCellView()
                c.identifier = cellID
                let label = NSTextField(labelWithString: "")
                label.translatesAutoresizingMaskIntoConstraints = false
                c.addSubview(label)
                c.textField = label
                NSLayoutConstraint.activate([
                    label.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 6),
                    label.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -6),
                    label.centerYAnchor.constraint(equalTo: c.centerYAnchor),
                ])
                return c
            }()
            cell.textField?.stringValue = text
            return cell

        default:
            return nil
        }
    }

    // MARK: - Actions

    @objc
    private func layoutSelectionChanged(_ sender: NSPopUpButton) {
        let row = sender.tag
        guard row >= 0, row < records.count else { return }
        let selected = sender.indexOfSelectedItem
        guard selected >= 0, selected < layouts.count else { return }

        let record = records[row]
        let layout = layouts[selected]
        store.setLayout(layout.id, forDisplayID: record.displayID)
        reloadAll(selectDisplayID: record.displayID)
    }
}

@MainActor
private final class DebugSettingsViewController: NSViewController {
    private let onDebugLoggingChanged: (Bool) -> Void

    private let checkbox = NSButton(checkboxWithTitle: "Enable debug logging", target: nil, action: nil)
    private let infoLabel = NSTextField(wrappingLabelWithString: "Write snap diagnostics to the PanePilot log file.")
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
    }

    // MARK: - State

    func refreshState() {
        checkbox.state = DebugLogger.shared.isEnabled() ? .on : .off
    }

    // MARK: - Layout

    private func configureUI() {
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        checkbox.target = self
        checkbox.action = #selector(toggleLogging)

        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        infoLabel.textColor = .secondaryLabelColor
        infoLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)

        openLogsButton.translatesAutoresizingMaskIntoConstraints = false
        openLogsButton.bezelStyle = .rounded
        openLogsButton.target = self
        openLogsButton.action = #selector(openLogs)

        view.addSubview(checkbox)
        view.addSubview(infoLabel)
        view.addSubview(openLogsButton)

        NSLayoutConstraint.activate([
            checkbox.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            checkbox.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 80),

            infoLabel.topAnchor.constraint(equalTo: checkbox.bottomAnchor, constant: 8),
            infoLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 80),
            infoLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            openLogsButton.topAnchor.constraint(equalTo: infoLabel.bottomAnchor, constant: 16),
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
        rightColumn.spacing = 0

        let legalLabel = NSTextField(
            wrappingLabelWithString: """
            License: AGPL-3.0-only.
            Source and distributed binaries use the same license.
            Copyright © 2026 Joakim and contributors.
            """
        )
        legalLabel.textColor = .secondaryLabelColor
        legalLabel.alignment = .left
        legalLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        legalLabel.translatesAutoresizingMaskIntoConstraints = false

        rightColumn.addArrangedSubview(legalLabel)

        container.addArrangedSubview(leftColumn)
        container.addArrangedSubview(divider)
        container.addArrangedSubview(rightColumn)

        view.addSubview(container)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 50),
            iconView.heightAnchor.constraint(equalToConstant: 50),
            divider.heightAnchor.constraint(equalToConstant: 78),
            leftColumn.widthAnchor.constraint(equalToConstant: 190),
            legalLabel.widthAnchor.constraint(equalToConstant: 175),
            container.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            container.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        ])
    }

    private var applicationVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? Bundle.main.infoDictionary?["CFBundleVersion"] as? String
            ?? "dev"
    }
}

private final class SettingsTabViewController: NSTabViewController {
    var onSelectionChanged: (() -> Void)?

    // MARK: - NSTabViewController

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        onSelectionChanged?()
    }
}
