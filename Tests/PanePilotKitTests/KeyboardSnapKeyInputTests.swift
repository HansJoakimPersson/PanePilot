import AppKit
import XCTest
@testable import PanePilotKit

final class KeyboardSnapKeyInputTests: XCTestCase {
    func testStartsKeyboardSnapWithConfiguredModifierOnEvent() {
        let shortcut = KeyboardSnapShortcut(modifiers: [.command], keyCode: 18)
        let input = KeyboardSnapKeyInput(shortcut: shortcut)

        XCTAssertTrue(
            input.startsKeyboardSnap(
                keyCode: 18,
                modifierFlags: [.command]
            )
        )
    }

    func testDoesNotStartKeyboardSnapWithMissingModifier() {
        let shortcut = KeyboardSnapShortcut(modifiers: [.command], keyCode: 18)
        let input = KeyboardSnapKeyInput(shortcut: shortcut)

        XCTAssertFalse(
            input.startsKeyboardSnap(
                keyCode: 18,
                modifierFlags: [.control]
            )
        )
    }

    func testDoesNotStartKeyboardSnapWithDifferentKey() {
        let shortcut = KeyboardSnapShortcut(modifiers: [.command], keyCode: 18)
        let input = KeyboardSnapKeyInput(shortcut: shortcut)

        XCTAssertFalse(
            input.startsKeyboardSnap(
                keyCode: 53,
                modifierFlags: [.command]
            )
        )
    }

    func testMapsAnsiAndNumpadDigits() {
        let input = KeyboardSnapKeyInput(shortcut: .defaultShortcut)

        XCTAssertEqual(input.digit(from: 18), 1)
        XCTAssertEqual(input.digit(from: 25), 9)
        XCTAssertEqual(input.digit(from: 83), 1)
        XCTAssertEqual(input.digit(from: 92), 9)
        XCTAssertNil(input.digit(from: KeyboardSnapKeyInput.cancelKeyCode))
    }

    func testEscapeCancelsFromLayoutSelection() {
        var progress = KeyboardSnapProgress()

        XCTAssertEqual(progress.handleEscape(), .cancel)
        XCTAssertNil(progress.selectedLayoutIndex)
    }

    func testEscapeReturnsFromZoneSelectionToLayoutSelection() {
        var progress = KeyboardSnapProgress()
        progress.selectLayout(at: 0)

        XCTAssertTrue(progress.isAwaitingZoneSelection)
        XCTAssertEqual(progress.handleEscape(), .returnToLayoutSelection)
        XCTAssertFalse(progress.isAwaitingZoneSelection)
        XCTAssertNil(progress.selectedLayoutIndex)
    }

    func testKeyboardSnapRouterConsumesConfiguredTrigger() {
        let router = KeyboardSnapEventRouter(shortcut: .defaultShortcut)

        XCTAssertEqual(
            router.action(
                keyCode: KeyboardSnapShortcut.defaultShortcut.keyCode,
                modifierFlags: KeyboardSnapShortcut.defaultShortcut.modifiers,
                keyboardSnapActive: false
            ),
            .activate
        )
    }

    func testKeyboardSnapRouterConsumesDigitsAndEscapeOnlyWhileActive() {
        let router = KeyboardSnapEventRouter(shortcut: .defaultShortcut)

        XCTAssertEqual(
            router.action(keyCode: 18, modifierFlags: [], keyboardSnapActive: true),
            .selectDigit(1)
        )
        XCTAssertEqual(
            router.action(
                keyCode: KeyboardSnapKeyInput.cancelKeyCode,
                modifierFlags: [],
                keyboardSnapActive: true
            ),
            .escape
        )
        XCTAssertEqual(
            router.action(keyCode: 18, modifierFlags: [], keyboardSnapActive: false),
            .passThrough
        )
    }

    func testKeyboardSnapRouterPassesUnrelatedKeysThrough() {
        let router = KeyboardSnapEventRouter(shortcut: .defaultShortcut)

        XCTAssertEqual(
            router.action(keyCode: 0, modifierFlags: [], keyboardSnapActive: true),
            .passThrough
        )
    }
}

final class ReliabilityPolicyTests: XCTestCase {
    func testRetriesTransientAccessibilityFailureOnlyOnce() {
        let error = AppError.axOperationFailed("set size", .failure)

        XCTAssertTrue(AXRetryPolicy.shouldRetry(error: error, attempt: 0))
        XCTAssertFalse(AXRetryPolicy.shouldRetry(error: error, attempt: 1))
    }

    func testDoesNotRetryInvalidArguments() {
        let error = AppError.invalidArguments("invalid frame")

        XCTAssertFalse(AXRetryPolicy.shouldRetry(error: error, attempt: 0))
    }
}
