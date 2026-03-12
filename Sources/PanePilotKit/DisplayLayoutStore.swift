import AppKit
import Foundation

enum SplitAxis {
    case vertical
    case horizontal
}

struct DisplayRecord: Codable {
    let displayID: String
    var name: String
    var isConnected: Bool
    var lastSeenAt: Date
    var layoutID: String
}

@MainActor
final class DisplayLayoutStore {
    private let displayFileURL: URL
    private let layoutsFileURL: URL
    private var recordsByID: [String: DisplayRecord] = [:]
    private var layoutsByID: [String: RegionLayout] = [:]
    private let builtInLayoutIDs: Set<String>

    init(layouts: [RegionLayout]) {
        self.builtInLayoutIDs = Set(layouts.map(\.id))
        let fm = FileManager.default
        let appSupportDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("PanePilot", isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("PanePilotAppSupport", isDirectory: true)
        try? fm.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
        self.displayFileURL = appSupportDir.appendingPathComponent("display-layouts.json")
        self.layoutsFileURL = appSupportDir.appendingPathComponent("layouts.json")

        self.layoutsByID = Dictionary(uniqueKeysWithValues: layouts.map { ($0.id, $0) })
        loadLayouts()
        load()
    }

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

    func setLayout(_ layoutID: String, forDisplayID displayID: String) {
        guard var record = recordsByID[displayID] else { return }
        guard layoutsByID[layoutID] != nil else { return }
        record.layoutID = layoutID
        recordsByID[displayID] = record
        persist()
    }

    func layout(for screen: NSScreen) -> RegionLayout {
        guard let id = ScreenProvider.displayID(for: screen) else {
            return defaultLayout
        }
        let idString = "\(id)"
        guard let record = recordsByID[idString],
              let layout = layoutsByID[record.layoutID] else {
            return defaultLayout
        }
        return layout
    }

    func layoutID(forDisplayID displayID: String) -> String {
        recordsByID[displayID]?.layoutID ?? defaultLayoutID
    }

    func allLayouts() -> [RegionLayout] {
        layoutsByID.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func addColumnLayout(name: String, columns: Int) -> RegionLayout {
        let clampedColumns = max(2, min(columns, 24))
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = cleanName.isEmpty ? "\(clampedColumns) Columns" : cleanName

        var uniqueName = baseName
        var suffix = 2
        while layoutsByID.values.contains(where: { $0.name.localizedCaseInsensitiveCompare(uniqueName) == .orderedSame }) {
            uniqueName = "\(baseName) \(suffix)"
            suffix += 1
        }

        let layoutID = "custom-\(UUID().uuidString.lowercased())"
        let fractions = Array(repeating: CGFloat(1), count: clampedColumns)
        let layout = RegionLayouts.makeColumns(id: layoutID, name: uniqueName, columnFractions: fractions)
        layoutsByID[layoutID] = layout
        persistLayouts()
        return layout
    }

    func addFullscreenLayout(name: String) -> RegionLayout {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = cleanName.isEmpty ? "New Layout" : cleanName

        var uniqueName = baseName
        var suffix = 2
        while layoutsByID.values.contains(where: { $0.name.localizedCaseInsensitiveCompare(uniqueName) == .orderedSame }) {
            uniqueName = "\(baseName) \(suffix)"
            suffix += 1
        }

        let layoutID = "custom-\(UUID().uuidString.lowercased())"
        let layout = RegionLayout(
            id: layoutID,
            name: uniqueName,
            regions: [
                RegionLayout.Region(
                    id: 1,
                    name: "Region 1",
                    normalizedFrame: CGRect(x: 0, y: 0, width: 1, height: 1)
                ),
            ]
        )
        layoutsByID[layoutID] = layout
        persistLayouts()
        return layout
    }

    @discardableResult
    func renameLayout(id: String, to name: String) -> Bool {
        guard isLayoutEditable(id: id), var layout = layoutsByID[id] else { return false }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        var uniqueName = trimmed
        var suffix = 2
        while layoutsByID.values.contains(where: { $0.id != id && $0.name.localizedCaseInsensitiveCompare(uniqueName) == .orderedSame }) {
            uniqueName = "\(trimmed) \(suffix)"
            suffix += 1
        }

        layout = RegionLayout(id: layout.id, name: uniqueName, regions: layout.regions)
        layoutsByID[id] = layout
        persistLayouts()
        return true
    }

    @discardableResult
    func removeLayout(id: String) -> Bool {
        guard layoutsByID[id] != nil else { return false }
        guard layoutsByID.count > 1 else { return false }
        guard !builtInLayoutIDs.contains(id) else { return false }

        layoutsByID.removeValue(forKey: id)
        let fallbackID = defaultLayoutID
        for key in recordsByID.keys {
            guard var record = recordsByID[key] else { continue }
            if record.layoutID == id {
                record.layoutID = fallbackID
                recordsByID[key] = record
            }
        }
        persistLayouts()
        persist()
        return true
    }

    func isLayoutEditable(id: String) -> Bool {
        !builtInLayoutIDs.contains(id)
    }

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
        layoutsByID[layout.id] = layout
        persistLayouts()
        return layout
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
        layoutsByID[layout.id] = layout
        persistLayouts()
        return layout
    }

    func resizeAdjacentRegions(layoutID: String, firstRegionID: Int, secondRegionID: Int, ratio: CGFloat) -> RegionLayout? {
        guard isLayoutEditable(id: layoutID), var layout = layoutsByID[layoutID], firstRegionID != secondRegionID else { return nil }
        guard let firstIndex = layout.regions.firstIndex(where: { $0.id == firstRegionID }),
              let secondIndex = layout.regions.firstIndex(where: { $0.id == secondRegionID }) else { return nil }

        let first = layout.regions[firstIndex]
        let second = layout.regions[secondIndex]
        let epsilon: CGFloat = 0.001
        let clampedRatio = max(0.05, min(0.95, ratio))

        var firstFrame = first.normalizedFrame
        var secondFrame = second.normalizedFrame

        let sameMinY = abs(firstFrame.minY - secondFrame.minY) < epsilon
        let sameHeight = abs(firstFrame.height - secondFrame.height) < epsilon
        let touchingHorizontally = abs(firstFrame.maxX - secondFrame.minX) < epsilon || abs(secondFrame.maxX - firstFrame.minX) < epsilon
        if sameMinY && sameHeight && touchingHorizontally {
            let unionMinX = min(firstFrame.minX, secondFrame.minX)
            let unionMaxX = max(firstFrame.maxX, secondFrame.maxX)
            let unionWidth = unionMaxX - unionMinX
            let leftIsFirst = firstFrame.minX < secondFrame.minX
            let leftWidth = unionWidth * (leftIsFirst ? clampedRatio : (1 - clampedRatio))
            let rightWidth = unionWidth - leftWidth
            guard leftWidth > 0.005, rightWidth > 0.005 else { return nil }

            let leftFrame = CGRect(x: unionMinX, y: firstFrame.minY, width: leftWidth, height: firstFrame.height)
            let rightFrame = CGRect(x: unionMinX + leftWidth, y: firstFrame.minY, width: rightWidth, height: firstFrame.height)
            if leftIsFirst {
                firstFrame = leftFrame
                secondFrame = rightFrame
            } else {
                firstFrame = rightFrame
                secondFrame = leftFrame
            }
        } else {
            let sameMinX = abs(firstFrame.minX - secondFrame.minX) < epsilon
            let sameWidth = abs(firstFrame.width - secondFrame.width) < epsilon
            let touchingVertically = abs(firstFrame.maxY - secondFrame.minY) < epsilon || abs(secondFrame.maxY - firstFrame.minY) < epsilon
            guard sameMinX && sameWidth && touchingVertically else { return nil }

            let unionMinY = min(firstFrame.minY, secondFrame.minY)
            let unionMaxY = max(firstFrame.maxY, secondFrame.maxY)
            let unionHeight = unionMaxY - unionMinY
            let bottomIsFirst = firstFrame.minY < secondFrame.minY
            let bottomHeight = unionHeight * (bottomIsFirst ? clampedRatio : (1 - clampedRatio))
            let topHeight = unionHeight - bottomHeight
            guard bottomHeight > 0.005, topHeight > 0.005 else { return nil }

            let bottomFrame = CGRect(x: firstFrame.minX, y: unionMinY, width: firstFrame.width, height: bottomHeight)
            let topFrame = CGRect(x: firstFrame.minX, y: unionMinY + bottomHeight, width: firstFrame.width, height: topHeight)
            if bottomIsFirst {
                firstFrame = bottomFrame
                secondFrame = topFrame
            } else {
                firstFrame = topFrame
                secondFrame = bottomFrame
            }
        }

        var regions = layout.regions
        regions[firstIndex] = RegionLayout.Region(id: first.id, name: first.name, normalizedFrame: firstFrame)
        regions[secondIndex] = RegionLayout.Region(id: second.id, name: second.name, normalizedFrame: secondFrame)
        layout = RegionLayout(id: layout.id, name: layout.name, regions: regions)
        layoutsByID[layout.id] = layout
        persistLayouts()
        return layout
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
        layoutsByID[layout.id] = updated
        persistLayouts()
        return updated
    }

    private var defaultLayout: RegionLayout {
        layoutsByID[RegionLayouts.threeColumn.id]
            ?? allLayouts().first
            ?? RegionLayouts.threeColumn
    }

    private var defaultLayoutID: String {
        defaultLayout.id
    }

    private func load() {
        guard let data = try? Data(contentsOf: displayFileURL) else { return }
        guard let decoded = try? JSONDecoder().decode([DisplayRecord].self, from: data) else { return }
        recordsByID = Dictionary(uniqueKeysWithValues: decoded.map { ($0.displayID, $0) })
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
        let custom = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
        // Merge persisted over defaults to keep user-created layouts.
        layoutsByID.merge(custom, uniquingKeysWith: { _, persisted in persisted })
    }

    private func persistLayouts() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let layouts = allLayouts()
        guard let data = try? encoder.encode(layouts) else { return }
        try? data.write(to: layoutsFileURL, options: .atomic)
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
