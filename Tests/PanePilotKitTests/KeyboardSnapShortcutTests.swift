import AppKit
import XCTest
@testable import PanePilotKit

final class KeyboardSnapShortcutTests: XCTestCase {
    func testRawValueRoundTripPreservesModifiersAndKeyCode() throws {
        let shortcut = KeyboardSnapShortcut(modifiers: [.command], keyCode: 18)

        let decoded = try XCTUnwrap(KeyboardSnapShortcut(rawValue: shortcut.rawValue))

        XCTAssertEqual(decoded, shortcut)
    }

    func testDefaultShortcutIsCommandOne() {
        XCTAssertEqual(KeyboardSnapShortcut.defaultShortcut.modifiers, [.command])
        XCTAssertEqual(KeyboardSnapShortcut.defaultShortcut.keyCode, 18)
        XCTAssertEqual(KeyboardSnapShortcut.defaultShortcut.displayName, "Command + 1")
    }

    func testShortcutMatchesExactModifierSet() {
        let shortcut = KeyboardSnapShortcut(modifiers: [.command], keyCode: 18)

        XCTAssertTrue(shortcut.matches(keyCode: 18, modifierFlags: [.command]))
        XCTAssertFalse(shortcut.matches(keyCode: 18, modifierFlags: [.control, .command]))
        XCTAssertFalse(shortcut.matches(keyCode: 53, modifierFlags: [.command]))
    }

    func testShortcutWarnsForEscapeAndSingleOption() {
        XCTAssertNotNil(KeyboardSnapShortcut(modifiers: [.control, .option], keyCode: 53).warningMessage)
        XCTAssertNotNil(KeyboardSnapShortcut(modifiers: [.option], keyCode: 49).warningMessage)
        XCTAssertNil(KeyboardSnapShortcut.defaultShortcut.warningMessage)
    }

    func testDragSnapModifierRawValueRoundTripPreservesModifierCombination() throws {
        let modifier = DragSnapModifier(modifiers: [.control, .option])

        let decoded = try XCTUnwrap(DragSnapModifier(rawValue: modifier.rawValue))

        XCTAssertEqual(decoded, modifier)
    }

    func testDragSnapModifierAcceptsLegacySingleModifierRawValue() throws {
        let decoded = try XCTUnwrap(DragSnapModifier(rawValue: "command"))

        XCTAssertEqual(decoded, .defaultModifier)
    }

    func testDragSnapModifierMatchesWhenRequiredModifiersAreHeld() {
        let modifier = DragSnapModifier(modifiers: [.command, .option])

        XCTAssertTrue(modifier.matches(modifierFlags: [.command, .option]))
        XCTAssertTrue(modifier.matches(modifierFlags: [.command, .option, .shift]))
        XCTAssertFalse(modifier.matches(modifierFlags: [.command]))
    }
}
