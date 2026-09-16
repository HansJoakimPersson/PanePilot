import Foundation
import XCTest
@testable import PanePilotKit

@MainActor
final class LayoutCatalogTests: XCTestCase {
    func testLayoutOrderPersistsAcrossStoreInstances() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let movedID = try XCTUnwrap(store.catalogItems().last?.layout.id)

        XCTAssertTrue(store.moveLayout(id: movedID, to: 2))
        let expectedOrder = store.catalogItems().map(\.layout.id)

        let reloaded = makeStore(at: directory)
        XCTAssertEqual(reloaded.catalogItems().map(\.layout.id), expectedOrder)
        XCTAssertEqual(reloaded.orderedLayouts().map(\.id), expectedOrder)
    }

    func testMovingFirstLayoutToEndUsesDropInsertionIndex() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstID = try XCTUnwrap(store.catalogItems().first?.layout.id)

        XCTAssertTrue(store.moveLayout(id: firstID, to: store.catalogItems().count))

        XCTAssertEqual(store.catalogItems().last?.layout.id, firstID)
    }

    func testLegacyCatalogWithFavoriteFieldStillLoads() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PanePilotLayoutCatalogTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let layoutID = RegionLayouts.split60x40.id
        let legacyJSON = """
        [{"layoutID":"\(layoutID)","isFavorite":true,"isVisible":false}]
        """
        try Data(legacyJSON.utf8).write(to: directory.appendingPathComponent("layout-catalog.json"))

        let store = makeStore(at: directory)

        XCTAssertFalse(try XCTUnwrap(store.catalogItems().first(where: { $0.layout.id == layoutID })).isVisible)
        let rewrittenCatalog = try String(
            contentsOf: directory.appendingPathComponent("layout-catalog.json"),
            encoding: .utf8
        )
        XCTAssertFalse(rewrittenCatalog.contains("isFavorite"))
    }

    func testPersistedBuiltInLayoutDoesNotOverrideCurrentDefinition() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PanePilotBuiltInLayoutTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let staleLayout = RegionLayout(
            id: RegionLayouts.widescreenTall.id,
            name: RegionLayouts.widescreenTall.name,
            regions: [
                .init(id: 1, name: "Main Pane", normalizedFrame: CGRect(x: 0, y: 0, width: 2.0 / 3.0, height: 1)),
                .init(id: 2, name: "Upper Stack", normalizedFrame: CGRect(x: 2.0 / 3.0, y: 0.5, width: 1.0 / 3.0, height: 0.5)),
                .init(id: 3, name: "Lower Stack", normalizedFrame: CGRect(x: 2.0 / 3.0, y: 0, width: 1.0 / 3.0, height: 0.5)),
            ]
        )
        let encoder = JSONEncoder()
        try encoder.encode([staleLayout]).write(to: directory.appendingPathComponent("layouts.json"))

        let store = makeStore(at: directory)
        let loaded = try XCTUnwrap(store.allLayouts().first(where: { $0.id == staleLayout.id }))
        let upperPane = try XCTUnwrap(loaded.regions.first(where: { $0.name == "Upper Stack" }))
        let lowerPane = try XCTUnwrap(loaded.regions.first(where: { $0.name == "Lower Stack" }))

        XCTAssertEqual(upperPane.id, 2)
        XCTAssertEqual(lowerPane.id, 3)
    }

    func testLegacyDisplayLayoutIDsAreMigratedToDisk() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PanePilotDisplayMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let legacyRecord = DisplayRecord(
            displayID: "display-1",
            name: "Test Display",
            isConnected: false,
            lastSeenAt: Date(timeIntervalSince1970: 0),
            layoutID: "wide"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([legacyRecord]).write(to: directory.appendingPathComponent("display-layouts.json"))

        _ = makeStore(at: directory)

        let migratedData = try Data(contentsOf: directory.appendingPathComponent("display-layouts.json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let migratedRecords = try decoder.decode([DisplayRecord].self, from: migratedData)
        XCTAssertEqual(migratedRecords.first?.layoutID, RegionLayouts.split60x40.id)
    }

    func testHiddenLayoutRemainsInCatalogButLeavesPickerOrder() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let layoutID = try XCTUnwrap(store.catalogItems().first?.layout.id)

        XCTAssertTrue(store.setVisible(false, for: layoutID))

        XCTAssertNotNil(store.catalogItems().first(where: { $0.layout.id == layoutID }))
        XCTAssertFalse(store.orderedLayouts().contains(where: { $0.id == layoutID }))

        let reloaded = makeStore(at: directory)
        XCTAssertFalse(try XCTUnwrap(reloaded.catalogItems().first(where: { $0.layout.id == layoutID })).isVisible)
    }

    func testLastVisibleLayoutCannotBeHidden() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let items = store.catalogItems()
        for item in items.dropLast() {
            XCTAssertTrue(store.setVisible(false, for: item.layout.id))
        }

        let lastVisibleID = try XCTUnwrap(store.orderedLayouts().only?.id)

        XCTAssertFalse(store.setVisible(false, for: lastVisibleID))
        XCTAssertEqual(store.orderedLayouts().map(\.id), [lastVisibleID])
    }

    func testNewCustomLayoutIsVisibleAndAppended() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let custom = store.addFullscreenLayout(name: "Writing")
        let lastItem = store.catalogItems().last

        XCTAssertEqual(lastItem?.layout.id, custom.id)
        XCTAssertEqual(lastItem?.isVisible, true)
        XCTAssertEqual(store.orderedLayouts().last?.id, custom.id)
    }

    func testInteractiveResizeCanDeferPersistenceUntilMouseUp() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        // Built-in layouts are read-only; use a custom two-column layout for resize testing.
        let layout = store.addColumnLayout(name: "Resize Test", columns: 2)
        let layoutsURL = directory.appendingPathComponent("layouts.json")
        // layouts.json is created by addColumnLayout, so baseline what actually exists now.
        let baselineExists = FileManager.default.fileExists(atPath: layoutsURL.path)

        let preview = store.resizeAdjacentRegions(
            layoutID: layout.id,
            firstRegionID: 1,
            secondRegionID: 2,
            ratio: 0.423,
            persistChanges: false
        )

        XCTAssertNotNil(preview)
        XCTAssertEqual(FileManager.default.fileExists(atPath: layoutsURL.path), baselineExists)

        let persisted = store.resizeAdjacentRegions(
            layoutID: layout.id,
            firstRegionID: 1,
            secondRegionID: 2,
            ratio: 0.423,
            persistChanges: true
        )

        XCTAssertNotNil(persisted)
        XCTAssertTrue(FileManager.default.fileExists(atPath: layoutsURL.path))
    }

    func testVerticalGroupResizeMovesTDivider() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let base = store.addFullscreenLayout(name: "T Divider")
        let splitColumns = try XCTUnwrap(
            store.splitRegion(layoutID: base.id, regionID: 1, axis: .vertical, ratio: 0.4)
        )
        let layout = try XCTUnwrap(
            store.splitRegion(layoutID: splitColumns.id, regionID: 2, axis: .horizontal, ratio: 0.5)
        )

        let resized = try XCTUnwrap(
            store.resizeAdjacentRegionGroups(
                layoutID: layout.id,
                firstRegionIDs: [1],
                secondRegionIDs: [2, 3],
                axis: .vertical,
                ratio: 0.55,
                persistChanges: false
            )
        )

        let left = try XCTUnwrap(resized.regions.first(where: { $0.id == 1 })?.normalizedFrame)
        let topRight = try XCTUnwrap(resized.regions.first(where: { $0.id == 2 })?.normalizedFrame)
        let bottomRight = try XCTUnwrap(resized.regions.first(where: { $0.id == 3 })?.normalizedFrame)
        XCTAssertEqual(left.width, 0.55, accuracy: 0.0001)
        XCTAssertEqual(topRight.minX, 0.55, accuracy: 0.0001)
        XCTAssertEqual(bottomRight.minX, 0.55, accuracy: 0.0001)
        XCTAssertEqual(topRight.width, 0.45, accuracy: 0.0001)
        XCTAssertEqual(bottomRight.width, 0.45, accuracy: 0.0001)
    }

    func testRemovingOnlyVisibleCustomLayoutRevealsFallback() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let custom = store.addFullscreenLayout(name: "Temporary")
        for item in store.catalogItems() where item.layout.id != custom.id {
            XCTAssertTrue(store.setVisible(false, for: item.layout.id))
        }

        XCTAssertEqual(store.orderedLayouts().map(\.id), [custom.id])
        XCTAssertTrue(store.removeLayout(id: custom.id))

        XCTAssertEqual(store.orderedLayouts().count, 1)
        XCTAssertNotEqual(store.orderedLayouts().first?.id, custom.id)
    }

    private func makeStore() throws -> (DisplayLayoutStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PanePilotLayoutCatalogTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (makeStore(at: directory), directory)
    }

    private func makeStore(at directory: URL) -> DisplayLayoutStore {
        DisplayLayoutStore(layouts: RegionLayouts.all, storageDirectory: directory)
    }
}

private extension Collection {
    var only: Element? {
        count == 1 ? first : nil
    }
}
