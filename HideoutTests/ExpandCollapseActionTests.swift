import AppKit
import XCTest
@testable import Hideout

final class ExpandCollapseActionTests: XCTestCase {
    func testMissingEventTogglesTheBar() {
        XCTAssertEqual(
            ExpandCollapseActionResolver.action(eventType: nil, optionPressed: false),
            .toggle
        )
    }

    func testLeftClickTogglesTheBar() {
        XCTAssertEqual(
            ExpandCollapseActionResolver.action(eventType: .leftMouseUp, optionPressed: false),
            .toggle
        )
    }

    func testRightClickOpensTheContextMenu() {
        XCTAssertEqual(
            ExpandCollapseActionResolver.action(eventType: .rightMouseUp, optionPressed: false),
            .contextMenu
        )
    }

    func testOptionClickTogglesSeparators() {
        XCTAssertEqual(
            ExpandCollapseActionResolver.action(eventType: .leftMouseUp, optionPressed: true),
            .toggleSeparators
        )
        XCTAssertEqual(
            ExpandCollapseActionResolver.action(eventType: .rightMouseUp, optionPressed: true),
            .toggleSeparators
        )
    }

    func testOtherMouseEventsToggleSeparators() {
        XCTAssertEqual(
            ExpandCollapseActionResolver.action(eventType: .otherMouseUp, optionPressed: false),
            .toggleSeparators
        )
    }
}
