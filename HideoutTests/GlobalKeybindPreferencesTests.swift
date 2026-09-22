import AppKit
import Carbon
import XCTest
@testable import Hideout

final class GlobalKeybindPreferencesTests: XCTestCase {
    private func makePreferences(
        function: Bool = false,
        control: Bool = false,
        command: Bool = false,
        shift: Bool = false,
        option: Bool = false,
        capsLock: Bool = false,
        characters: String? = "k",
        keyCode: UInt32 = 40
    ) -> GlobalKeybindPreferences {
        GlobalKeybindPreferences(
            function: function,
            control: control,
            command: command,
            shift: shift,
            option: option,
            capsLock: capsLock,
            carbonFlags: 0,
            characters: characters,
            keyCode: keyCode
        )
    }

    func testFunctionKeysUseTheirNamesInsteadOfFnPrefix() {
        let preferences = makePreferences(function: true, characters: "x", keyCode: 79)

        XCTAssertEqual(preferences.description, "F18")
    }

    func testModifierOrderMatchesMenuBarShortcutDisplay() {
        let preferences = makePreferences(
            function: true,
            control: true,
            command: true,
            shift: true,
            option: true,
            capsLock: true,
            characters: "k"
        )

        XCTAssertEqual(preferences.description, "Fn⌃⌥⌘⇧⇪K")
    }

    func testSpecialKeysUseReadableSymbols() {
        XCTAssertEqual(makePreferences(keyCode: 36).description, "⏎")
        XCTAssertEqual(makePreferences(keyCode: 51).description, "⌫")
        XCTAssertEqual(makePreferences(keyCode: 49).description, "⎵")
    }

    func testMissingCharactersProduceOnlyTheModifierDescription() {
        let preferences = makePreferences(command: true, characters: nil)

        XCTAssertEqual(preferences.description, "⌘")
    }

    func testCarbonFlagsIncludeOnlyShortcutModifiers() {
        let flags: NSEvent.ModifierFlags = [.command, .option, .control, .shift, .function, .capsLock]
        let expected = UInt32(cmdKey) | UInt32(optionKey) | UInt32(controlKey) | UInt32(shiftKey)

        XCTAssertEqual(flags.carbonFlags, expected)
    }

    func testCarbonFlagsAreZeroWithoutShortcutModifiers() {
        XCTAssertEqual(NSEvent.ModifierFlags([.function, .capsLock]).carbonFlags, 0)
    }
}
