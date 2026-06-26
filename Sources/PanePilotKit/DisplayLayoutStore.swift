import AppKit
import Foundation

/// The axis along which a region is split.
enum SplitAxis {
    case vertical
    case horizontal
}

/// Persisted record that tracks which layout is assigned to a specific physical display.
///
/// Records are keyed by `displayID` (a string representation of `CGDirectDisplayID`). The
/// `isConnected` flag reflects whether the display was present the last time
/// `refreshConnectedDisplays()` ran. Records for disconnected displays are retained so the
/// assignment is remembered when the display is reconnected.
struct DisplayRecord: Codable {
    /// String form of `CGDirectDisplayID` — stable for the lifetime of the display connection.
    let displayID: String
    /// Human-readable display name from `NSScreen.localizedName`.
    var name: String
    /// Whether the display is currently connected.
    var isConnected: Bool
    /// The last time this display was seen as connected.
    var lastSeenAt: Date
    /// The ID of the `RegionLayout` assigned to this display.
    var layoutID: String
}

/// User-controlled presentation metadata for one layout in the picker catalog.
struct LayoutCatalogItem {
    let layout: RegionLayout
    let isVisible: Bool
    let isBuiltIn: Bool
}

private struct PersistedLayoutCatalogEntry: Codable, Equatable {
    let layoutID: String
    var isVisible: Bool
}

/// The central store for layout definitions and per-display layout assignments.
///
/// `DisplayLayoutStore` maintains two parallel collections:
/// - **Layout catalog**: the full set of available `RegionLayout` values (built-ins + custom).
/// - **Display registry**: `DisplayRecord` entries mapping physical displays to layouts.
///
/// Layout definitions, catalog metadata, and display records are persisted to separate JSON
/// files under `~/Library/Application Support/PanePilot/`.
/// On load, legacy layout IDs are migrated through `RegionLayouts.canonicalLayoutID(for:)`.
///
/// All mutation methods must be called on the main actor. Read-only query methods
/// (`allLayouts()`, `layout(for:)`, etc.) may be called from any main-thread context.
@MainActor
final class DisplayLayoutStore {
    // Display assignments and layout definitions are persisted separately so connected
    // display state can evolve without rewriting the full set of available layouts.
    private let displayFileURL: URL
    private let layoutsFileURL: URL
    private let catalogFileURL: URL
    private var recordsByID: [String: DisplayRecord] = [:]
    private var layoutsByID: [String: RegionLayout] = [:]
    private var catalogEntries: [PersistedLayoutCatalogEntry] = []
    private let builtInLayoutIDs: Set<String>

    // MARK: - Initialization

    init(layouts: [RegionLayout], storageDirectory: URL? = nil) {
        self.builtInLayoutIDs = Set(layouts.map(\.id))
        let fm = FileManager.default
        let appSupportDir = storageDirectory
            ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("PanePilot", isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("PanePilotAppSupport", isDirectory: true)
        try? fm.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
        self.displayFileURL = appSupportDir.appendingPathComponent("display-layouts.json")
        self.layoutsFileURL = appSupportDir.appendingPathComponent("layouts.json")
        self.catalogFileURL = appSupportDir.appendingPathComponent("layout-catalog.json")

        self.layoutsByID = Dictionary(uniqueKeysWithValues: layouts.map { ($0.id, $0) })
        loadLayouts()
        loadCatalog()
        reconcileCatalog()
        load()
    }

    // MARK: - Display Assignments

    /// Syncs the display registry against the currently connected screens.
    ///
    /// Connected displays get their `isConnected` flag set to `true` and `lastSeenAt` updated.
    /// Displays no longer in `NSScreen.screens` are marked `isConnected = false` but kept in
    /// the registry so their layout assignment is remembered when they reconnect.
    func refreshConnectedDisplays() {
        let now = Date()
        var connectedIDs = Set<String>()

        for screen in NSScreen.screens {
            guard let id = ScreenProvider.displayID(for: screen) else { continue }
            let idString = "\(id)"
            connectedIDs.insert(idString)

            if var existing = recordsByID[idString] {
                existing.isConnected = true
                existing.lastSeenAt = now
                existing.name = screen.localizedName
                recordsByID[idString] = existing
            } else {
                recordsByID[idString] = DisplayRecord(
                    displayID: idString,
                    name: screen.localizedName,
                    isConnected: true,
                    lastSeenAt: now,
                    layoutID: defaultLayoutID
                )
            }
        }

        for key in recordsByID.keys {
            if !connectedIDs.contains(key) {
                var record = recordsByID[key]!
                record.isConnected = false
                recordsByID[key] = record
            }
        }
        persist()
    }

    func allRecords() -> [DisplayRecord] {
        recordsByID.values.sorted {
            if $0.isConnected != $1.isConnected {
                return $0.isConnected && !$1.isConnected
            }
            if $0.lastSeenAt != $1.lastSeenAt {
                return $0.lastSeenAt > $1.lastSeenAt
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    // MARK: - Layout Catalog

    /// Returns all layouts in the user's catalog order, including hidden layouts.
    func allLayouts() -> [RegionLayout] {
        catalogItems().map(\.layout)
    }

    func catalogItems() -> [LayoutCatalogItem] {
        catalogEntries.compactMap { entry in
            guard let layout = layoutsByID[entry.layoutID] else { return nil }
            return LayoutCatalogItem(
                layout: layout,
                isVisible: entry.isVisible,
                isBuiltIn: builtInLayoutIDs.contains(layout.id)
            )
        }
    }

    /// Returns all layouts in snap-picker display order.
    ///
    /// Hidden layouts remain editable in Settings but are omitted from the picker and keyboard
    /// numbering. The remaining order is entirely user-controlled.
    func orderedLayouts() -> [RegionLayout] {
        catalogItems().filter(\.isVisible).map(\.layout)
    }

    @discardableResult
    func setVisible(_ visible: Bool, for layoutID: String) -> Bool {
        guard let index = catalogEntries.firstIndex(where: { $0.layoutID == layoutID }) else { return false }
        guard catalogEntries[index].isVisible != visible else { return true }
        if !visible {
            let visibleCount = catalogEntries.lazy.filter(\.isVisible).count
            guard visibleCount > 1 else { return false }
        }
        catalogEntries[index].isVisible = visible
        persistCatalog()
        return true
    }

    @discardableResult
    func moveLayout(id layoutID: String, to insertionIndex: Int) -> Bool {
        guard let sourceIndex = catalogEntries.firstIndex(where: { $0.layoutID == layoutID }) else { return false }
        var destinationIndex = max(0, min(insertionIndex, catalogEntries.count))
        if sourceIndex < destinationIndex {
            destinationIndex -= 1
        }
        guard sourceIndex != destinationIndex else { return true }
        let entry = catalogEntries.remove(at: sourceIndex)
        catalogEntries.insert(entry, at: destinationIndex)
        persistCatalog()
        return true
    }

    func addColumnLayout(name: String, columns: Int) -> RegionLayout {
        let clampedColumns = max(2, min(columns, 24))
        let fractions = Array(repeating: CGFloat(1), count: clampedColumns)
        return saveLayout(
            RegionLayouts.makeColumns(
                id: customLayoutID(),
                name: uniqueLayoutName(from: name, fallback: "\(clampedColumns) Columns"),
                columnFractions: fractions
            )
        )
    }

    func addFullscreenLayout(name: String) -> RegionLayout {
        saveLayout(
            RegionLayout(
                id: customLayoutID(),
                name: uniqueLayoutName(from: name, fallback: "New Layout"),
                regions: [
                    RegionLayout.Region(
                        id: 1,
                        name: "Region 1",
                        normalizedFrame: CGRect(x: 0, y: 0, width: 1, height: 1)
                    ),
                ]
            )
        )
    }

    @discardableResult
    func renameLayout(id: String, to name: String) -> Bool {
        guard isLayoutEditable(id: id), let layout = layoutsByID[id] else { return false }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        _ = saveLayout(
            RegionLayout(
                id: layout.id,
                name: uniqueLayoutName(from: trimmed, fallback: trimmed, excluding: id),
                regions: layout.regions
            )
        )
        return true
    }

    @discardableResult
    func removeLayout(id: String) -> Bool {
        guard layoutsByID[id] != nil else { return false }
        guard layoutsByID.count > 1 else { return false }
        guard !builtInLayoutIDs.contains(id) else { return false }

        layoutsByID.removeValue(forKey: id)
        catalogEntries.removeAll { $0.layoutID == id }
        ensureVisibleCatalogEntry()
        let fallbackID = defaultLayoutID
        for key in recordsByID.keys {
            guard var record = recordsByID[key] else { continue }
            if record.layoutID == id {
                record.layoutID = fallbackID
                recordsByID[key] = record
            }
        }
        persistLayouts()
        persistCatalog()
        persist()
        return true
    }

    /// Returns `true` if the layout with the given ID can be renamed, edited, or deleted.
    ///
    /// Built-in layouts are read-only; only user-created layouts are editable.
    func isLayoutEditable(id: String) -> Bool {
        !builtInLayoutIDs.contains(id)
    }

    // MARK: - Layout Editing

    func splitRegion(layoutID: String, regionID: Int, axis: SplitAxis, ratio: CGFloat) -> RegionLayout? {
        guard isLayoutEditable(id: layoutID), var layout = layoutsByID[layoutID] else { return nil }
        guard layout.regions.count < 64 else { return nil }
        guard let regionIndex = layout.regions.firstIndex(where: { $0.id == regionID }) else { return nil }
        let clampedRatio = max(0.05, min(ratio, 0.95))

        let region = layout.regions[regionIndex]
        let first: RegionLayout.Region
        let second: RegionLayout.Region

        switch axis {
        case .vertical:
            let firstWidth = region.normalizedFrame.width * clampedRatio
            let secondWidth = region.normalizedFrame.width - firstWidth
            guard firstWidth > 0.005, secondWidth > 0.005 else { return nil }
            first = RegionLayout.Region(
                id: 0,
                name: "",
                normalizedFrame: CGRect(
                    x: region.normalizedFrame.minX,
                    y: region.normalizedFrame.minY,
                    width: firstWidth,
                    height: region.normalizedFrame.height
                )
            )
            second = RegionLayout.Region(
                id: 0,
                name: "",
                normalizedFrame: CGRect(
                    x: region.normalizedFrame.minX + firstWidth,
                    y: region.normalizedFrame.minY,
                    width: secondWidth,
                    height: region.normalizedFrame.height
                )
            )
        case .horizontal:
            let firstHeight = region.normalizedFrame.height * clampedRatio
            let secondHeight = region.normalizedFrame.height - firstHeight
            guard firstHeight > 0.005, secondHeight > 0.005 else { return nil }
            first = RegionLayout.Region(
                id: 0,
                name: "",
                normalizedFrame: CGRect(
                    x: region.normalizedFrame.minX,
                    y: region.normalizedFrame.minY,
                    width: region.normalizedFrame.width,
                    height: firstHeight
                )
            )
            second = RegionLayout.Region(
                id: 0,
                name: "",
                normalizedFrame: CGRect(
                    x: region.normalizedFrame.minX,
                    y: region.normalizedFrame.minY + firstHeight,
                    width: region.normalizedFrame.width,
                    height: secondHeight
                )
            )
        }

        var regions = layout.regions
        regions.remove(at: regionIndex)
        regions.append(first)
        regions.append(second)
        regions = reindexRegions(regions)

        layout = RegionLayout(id: layout.id, name: layout.name, regions: regions)
        return saveLayout(layout)
    }

    func canMergeRegions(layoutID: String, firstRegionID: Int, secondRegionID: Int) -> Bool {
        guard let layout = layoutsByID[layoutID], firstRegionID != secondRegionID else { return false }
        guard let first = layout.regions.first(where: { $0.id == firstRegionID }),
              let second = layout.regions.first(where: { $0.id == secondRegionID }) else { return false }
        return mergedRegionFrame(first: first.normalizedFrame, second: second.normalizedFrame) != nil
    }

    func mergeRegions(layoutID: String, firstRegionID: Int, secondRegionID: Int) -> RegionLayout? {
        guard isLayoutEditable(id: layoutID), var layout = layoutsByID[layoutID], firstRegionID != secondRegionID else { return nil }
        guard let firstIndex = layout.regions.firstIndex(where: { $0.id == firstRegionID }),
              let secondIndex = layout.regions.firstIndex(where: { $0.id == secondRegionID }) else { return nil }

        let first = layout.regions[firstIndex]
        let second = layout.regions[secondIndex]
        guard let merged = mergedRegionFrame(first: first.normalizedFrame, second: second.normalizedFrame) else { return nil }

        var regions = layout.regions.enumerated().compactMap { index, region -> RegionLayout.Region? in
            if index == firstIndex || index == secondIndex {
                return nil
            }
            return region
        }
        regions.append(
            RegionLayout.Region(
                id: 0,
                name: "",
                normalizedFrame: merged
            )
        )
        regions = reindexRegions(regions)
        layout = RegionLayout(id: layout.id, name: layout.name, regions: regions)
        return saveLayout(layout)
    }

    func resizeAdjacentRegions(
        layoutID: String,
        firstRegionID: Int,
        secondRegionID: Int,
        ratio: CGFloat,
        persistChanges: Bool = true
    ) -> RegionLayout? {
        guard let layout = layoutsByID[layoutID],
              let first = layout.regions.first(where: { $0.id == firstRegionID }),
              let second = layout.regions.first(where: { $0.id == secondRegionID }) else { return nil }

        let epsilon: CGFloat = 0.001

        let touchingHorizontally = abs(first.normalizedFrame.maxX - second.normalizedFrame.minX) < epsilon
            || abs(second.normalizedFrame.maxX - first.normalizedFrame.minX) < epsilon
        if touchingHorizontally {
            let firstIsLeft = first.normalizedFrame.minX < second.normalizedFrame.minX
            return resizeAdjacentRegionGroups(
                layoutID: layoutID,
                firstRegionIDs: [firstIsLeft ? firstRegionID : secondRegionID],
                secondRegionIDs: [firstIsLeft ? secondRegionID : firstRegionID],
                axis: .vertical,
                ratio: firstIsLeft ? ratio : 1 - ratio,
                persistChanges: persistChanges
            )
        }

        let touchingVertically = abs(first.normalizedFrame.maxY - second.normalizedFrame.minY) < epsilon
            || abs(second.normalizedFrame.maxY - first.normalizedFrame.minY) < epsilon
        guard touchingVertically else { return nil }
        let firstIsBottom = first.normalizedFrame.minY < second.normalizedFrame.minY
        return resizeAdjacentRegionGroups(
            layoutID: layoutID,
            firstRegionIDs: [firstIsBottom ? firstRegionID : secondRegionID],
            secondRegionIDs: [firstIsBottom ? secondRegionID : firstRegionID],
            axis: .horizontal,
            ratio: firstIsBottom ? ratio : 1 - ratio,
            persistChanges: persistChanges
        )
    }

    func resizeAdjacentRegionGroups(
        layoutID: String,
        firstRegionIDs: [Int],
        secondRegionIDs: [Int],
        axis: SplitAxis,
        ratio: CGFloat,
        persistChanges: Bool = true
    ) -> RegionLayout? {
        guard isLayoutEditable(id: layoutID), var layout = layoutsByID[layoutID] else { return nil }
        let firstIDs = Set(firstRegionIDs)
        let secondIDs = Set(secondRegionIDs)
        guard !firstIDs.isEmpty, !secondIDs.isEmpty, firstIDs.isDisjoint(with: secondIDs) else { return nil }
        let clampedRatio = max(0.05, min(0.95, ratio))
        var regions = layout.regions
        let firstRegions = regions.filter { firstIDs.contains($0.id) }
        let secondRegions = regions.filter { secondIDs.contains($0.id) }
        guard firstRegions.count == firstIDs.count, secondRegions.count == secondIDs.count else { return nil }

        switch axis {
        case .vertical:
            let unionMinX = (firstRegions + secondRegions).map(\.normalizedFrame.minX).min() ?? 0
            let unionMaxX = (firstRegions + secondRegions).map(\.normalizedFrame.maxX).max() ?? 1
            let newX = unionMinX + ((unionMaxX - unionMinX) * clampedRatio)
            guard newX - unionMinX > 0.005, unionMaxX - newX > 0.005 else { return nil }

            for index in regions.indices {
                let region = regions[index]
                var frame = region.normalizedFrame
                if firstIDs.contains(region.id) {
                    let width = newX - frame.minX
                    guard width > 0.005 else { return nil }
                    frame.size.width = width
                } else if secondIDs.contains(region.id) {
                    let maxX = frame.maxX
                    let width = maxX - newX
                    guard width > 0.005 else { return nil }
                    frame.origin.x = newX
                    frame.size.width = width
                } else {
                    continue
                }
                regions[index] = RegionLayout.Region(id: region.id, name: region.name, normalizedFrame: frame)
            }
        case .horizontal:
            let unionMinY = (firstRegions + secondRegions).map(\.normalizedFrame.minY).min() ?? 0
            let unionMaxY = (firstRegions + secondRegions).map(\.normalizedFrame.maxY).max() ?? 1
            let newY = unionMinY + ((unionMaxY - unionMinY) * clampedRatio)
            guard newY - unionMinY > 0.005, unionMaxY - newY > 0.005 else { return nil }

            for index in regions.indices {
                let region = regions[index]
                var frame = region.normalizedFrame
                if firstIDs.contains(region.id) {
                    let height = newY - frame.minY
                    guard height > 0.005 else { return nil }
                    frame.size.height = height
                } else if secondIDs.contains(region.id) {
                    let maxY = frame.maxY
                    let height = maxY - newY
                    guard height > 0.005 else { return nil }
                    frame.origin.y = newY
                    frame.size.height = height
                } else {
                    continue
                }
                regions[index] = RegionLayout.Region(id: region.id, name: region.name, normalizedFrame: frame)
            }
        }

        layout = RegionLayout(id: layout.id, name: layout.name, regions: regions)
        return saveLayout(layout, persistChanges: persistChanges)
    }

    func setEqualColumns(layoutID: String, columns: Int) -> RegionLayout? {
        guard isLayoutEditable(id: layoutID), let layout = layoutsByID[layoutID] else { return nil }
        let clampedColumns = max(2, min(columns, 24))
        let fractions = Array(repeating: CGFloat(1), count: clampedColumns)
        let updated = RegionLayouts.makeColumns(
            id: layout.id,
            name: layout.name,
            columnFractions: fractions
        )
        return saveLayout(updated)
    }

    // MARK: - Persistence

    private var defaultLayout: RegionLayout {
        layoutsByID[RegionLayouts.split60x40.id]
            ?? allLayouts().first
            ?? RegionLayouts.split60x40
    }

    private var defaultLayoutID: String {
        defaultLayout.id
    }

    private func load() {
        guard let data = try? Data(contentsOf: displayFileURL) else { return }
        guard let decoded = try? JSONDecoder().decode([DisplayRecord].self, from: data) else { return }
        recordsByID = Dictionary(
            uniqueKeysWithValues: decoded.map { record in
                var migratedRecord = record
                migratedRecord.layoutID = RegionLayouts.canonicalLayoutID(for: record.layoutID)
                return (migratedRecord.displayID, migratedRecord)
            }
        )
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let sorted = allRecords()
        guard let data = try? encoder.encode(sorted) else { return }
        try? data.write(to: displayFileURL, options: .atomic)
    }

    private func loadLayouts() {
        guard let data = try? Data(contentsOf: layoutsFileURL) else { return }
        guard let decoded = try? JSONDecoder().decode([RegionLayout].self, from: data) else { return }
        let custom = Dictionary(uniqueKeysWithValues: decoded.compactMap { layout -> (String, RegionLayout)? in
            let canonicalID = RegionLayouts.canonicalLayoutID(for: layout.id)

            // Retired built-in IDs are intentionally replaced by the new built-in catalog,
            // so skip their persisted geometry instead of letting stale defaults override
            // the current shipped layouts.
            if layout.id != canonicalID, builtInLayoutIDs.contains(canonicalID) {
                return nil
            }

            let migratedLayout = RegionLayout(
                id: canonicalID,
                name: layout.name,
                regions: layout.regions
            )
            return (migratedLayout.id, migratedLayout)
        })
        // Merge persisted over defaults to keep user-created layouts.
        layoutsByID.merge(custom, uniquingKeysWith: { _, persisted in persisted })
    }

    private func loadCatalog() {
        guard let data = try? Data(contentsOf: catalogFileURL),
              let decoded = try? JSONDecoder().decode([PersistedLayoutCatalogEntry].self, from: data) else { return }
        catalogEntries = decoded
    }

    private func reconcileCatalog() {
        var seen = Set<String>()
        var reconciled = catalogEntries.compactMap { entry -> PersistedLayoutCatalogEntry? in
            let canonicalID = RegionLayouts.canonicalLayoutID(for: entry.layoutID)
            guard layoutsByID[canonicalID] != nil, seen.insert(canonicalID).inserted else { return nil }
            return PersistedLayoutCatalogEntry(
                layoutID: canonicalID,
                isVisible: entry.isVisible
            )
        }

        for layoutID in defaultCatalogOrder where !seen.contains(layoutID) {
            reconciled.append(PersistedLayoutCatalogEntry(layoutID: layoutID, isVisible: true))
            seen.insert(layoutID)
        }

        let remainingIDs = layoutsByID.values
            .filter { !seen.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map(\.id)
        reconciled.append(contentsOf: remainingIDs.map {
            PersistedLayoutCatalogEntry(layoutID: $0, isVisible: true)
        })

        catalogEntries = reconciled
        ensureVisibleCatalogEntry()
        persistCatalog()
    }

    private func ensureVisibleCatalogEntry() {
        guard !catalogEntries.isEmpty, !catalogEntries.contains(where: \.isVisible) else { return }
        catalogEntries[0].isVisible = true
    }

    private var defaultCatalogOrder: [String] {
        let preferredBuiltIns = [
            RegionLayouts.split60x40.id,
            RegionLayouts.split40x60.id,
            RegionLayouts.widescreenTall.id,
            RegionLayouts.widescreenTallMirror.id,
            RegionLayouts.column.id,
            RegionLayouts.threeColumnMiddle.id,
        ]
        return preferredBuiltIns.filter { layoutsByID[$0] != nil }
    }

    private func persistLayouts() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let layouts = allLayouts()
        guard let data = try? encoder.encode(layouts) else { return }
        try? data.write(to: layoutsFileURL, options: .atomic)
    }

    private func persistCatalog() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(catalogEntries) else { return }
        try? data.write(to: catalogFileURL, options: .atomic)
    }

    // MARK: - Layout Utilities

    @discardableResult
    private func saveLayout(_ layout: RegionLayout, persistChanges: Bool = true) -> RegionLayout {
        layoutsByID[layout.id] = layout
        if !catalogEntries.contains(where: { $0.layoutID == layout.id }) {
            catalogEntries.append(
                PersistedLayoutCatalogEntry(layoutID: layout.id, isVisible: true)
            )
            if persistChanges {
                persistCatalog()
            }
        }
        if persistChanges {
            persistLayouts()
        }
        return layout
    }

    private func customLayoutID() -> String {
        "custom-\(UUID().uuidString.lowercased())"
    }

    private func uniqueLayoutName(from proposedName: String, fallback: String, excluding excludedID: String? = nil) -> String {
        let trimmed = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = trimmed.isEmpty ? fallback : trimmed

        var uniqueName = baseName
        var suffix = 2
        while layoutsByID.values.contains(where: {
            $0.id != excludedID && $0.name.localizedCaseInsensitiveCompare(uniqueName) == .orderedSame
        }) {
            uniqueName = "\(baseName) \(suffix)"
            suffix += 1
        }
        return uniqueName
    }

    private func reindexRegions(_ regions: [RegionLayout.Region]) -> [RegionLayout.Region] {
        let sorted = regions.sorted {
            if abs($0.normalizedFrame.minY - $1.normalizedFrame.minY) > 0.0001 {
                return $0.normalizedFrame.minY < $1.normalizedFrame.minY
            }
            return $0.normalizedFrame.minX < $1.normalizedFrame.minX
        }
        return sorted.enumerated().map { index, region in
            RegionLayout.Region(
                id: index + 1,
                name: "Region \(index + 1)",
                normalizedFrame: region.normalizedFrame
            )
        }
    }

    private func mergedRegionFrame(first: CGRect, second: CGRect) -> CGRect? {
        let epsilon: CGFloat = 0.001

        let sameMinY = abs(first.minY - second.minY) < epsilon
        let sameHeight = abs(first.height - second.height) < epsilon
        let touchingHorizontally = abs(first.maxX - second.minX) < epsilon || abs(second.maxX - first.minX) < epsilon
        if sameMinY && sameHeight && touchingHorizontally {
            return CGRect(
                x: min(first.minX, second.minX),
                y: first.minY,
                width: first.width + second.width,
                height: first.height
            )
        }

        let sameMinX = abs(first.minX - second.minX) < epsilon
        let sameWidth = abs(first.width - second.width) < epsilon
        let touchingVertically = abs(first.maxY - second.minY) < epsilon || abs(second.maxY - first.minY) < epsilon
        if sameMinX && sameWidth && touchingVertically {
            return CGRect(
                x: first.minX,
                y: min(first.minY, second.minY),
                width: first.width,
                height: first.height + second.height
            )
        }

        return nil
    }
}
