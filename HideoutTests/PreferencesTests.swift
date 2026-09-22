import XCTest
@testable import Hideout

@MainActor
final class PreferencesTests: XCTestCase {
    func testGlobalKeyRoundTripUsesTheCodableRepresentation() {
        let defaults = UserDefaults.standard
        let previousValue = defaults.object(forKey: UserDefaults.Key.globalKey)
        defer { restore(previousValue, forKey: UserDefaults.Key.globalKey) }

        let expected = GlobalKeybindPreferences(
            function: false,
            control: true,
            command: true,
            shift: false,
            option: true,
            capsLock: false,
            carbonFlags: 12,
            characters: "k",
            keyCode: 40
        )

        Preferences.globalKey = expected

        XCTAssertEqual(Preferences.globalKey?.description, expected.description)
        XCTAssertEqual(Preferences.globalKey?.carbonFlags, expected.carbonFlags)
        XCTAssertEqual(Preferences.globalKey?.keyCode, expected.keyCode)
    }

    func testAutoHideDelayPersistsInUserDefaults() {
        let defaults = UserDefaults.standard
        let previousValue = defaults.object(forKey: UserDefaults.Key.numberOfSecondForAutoHide)
        defer { restore(previousValue, forKey: UserDefaults.Key.numberOfSecondForAutoHide) }

        Preferences.numberOfSecondForAutoHide = 30

        XCTAssertEqual(Preferences.numberOfSecondForAutoHide, 30)
    }

    private func restore(_ value: Any?, forKey key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
