import AppKit
import XCTest
@testable import Hideout

final class ExpandCollapseActionTests: XCTestCase {
    func testMissingEventTogglesTheBar() {
        XCTAssertEqual(
            ExpandCollapseActionResolver.action(eventType: nil),
            .toggle
        )
    }

    func testLeftClickTogglesTheBar() {
        XCTAssertEqual(
            ExpandCollapseActionResolver.action(eventType: .leftMouseUp),
            .toggle
        )
    }

    func testRightClickOpensTheContextMenu() {
        XCTAssertEqual(
            ExpandCollapseActionResolver.action(eventType: .rightMouseUp),
            .contextMenu
        )
    }

    func testOtherMouseEventsToggleTheBar() {
        XCTAssertEqual(
            ExpandCollapseActionResolver.action(eventType: .otherMouseUp),
            .toggle
        )
    }
}
