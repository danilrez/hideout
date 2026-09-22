import CoreGraphics
import XCTest
@testable import Hideout

final class StatusBarLayoutTests: XCTestCase {
    func testCollapseUnitStaysBelowTheMacOS27StatusItemCliff() {
        XCTAssertEqual(StatusBarLayout.collapseUnit(narrowestDisplayWidth: 1728), 800)
        XCTAssertEqual(StatusBarLayout.collapseUnit(narrowestDisplayWidth: 400), 200)
    }

    func testSpacerCountCoversTheWidestDisplayWithoutExceedingCapacity() {
        XCTAssertEqual(
            StatusBarLayout.activeSpacerCount(
                widestDisplayWidth: 1800,
                collapseUnit: 800,
                availableSpacers: 6
            ),
            2
        )
        XCTAssertEqual(
            StatusBarLayout.activeSpacerCount(
                widestDisplayWidth: 5800,
                collapseUnit: 800,
                availableSpacers: 6
            ),
            6
        )
    }

    func testSpacerCountIsZeroForInvalidOrEmptyInputs() {
        XCTAssertEqual(
            StatusBarLayout.activeSpacerCount(
                widestDisplayWidth: 1800,
                collapseUnit: 0,
                availableSpacers: 6
            ),
            0
        )
        XCTAssertEqual(
            StatusBarLayout.activeSpacerCount(
                widestDisplayWidth: 1800,
                collapseUnit: 800,
                availableSpacers: 0
            ),
            0
        )
    }
}
