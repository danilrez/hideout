import XCTest
@testable import Hideout

final class SelectedSecondTests: XCTestCase {
    func testSelectionsMapToTheirAutoHideDelays() {
        XCTAssertEqual(SelectedSecond.fiveSeconds.toSeconds(), 5)
        XCTAssertEqual(SelectedSecond.tenSeconds.toSeconds(), 10)
        XCTAssertEqual(SelectedSecond.fifteenSeconds.toSeconds(), 15)
        XCTAssertEqual(SelectedSecond.thirdtySeconds.toSeconds(), 30)
        XCTAssertEqual(SelectedSecond.oneMinus.toSeconds(), 60)
    }

    func testAutoHideDelaysMapBackToPopupPositions() {
        XCTAssertEqual(SelectedSecond.secondToPossition(seconds: 5), 0)
        XCTAssertEqual(SelectedSecond.secondToPossition(seconds: 10), 1)
        XCTAssertEqual(SelectedSecond.secondToPossition(seconds: 15), 2)
        XCTAssertEqual(SelectedSecond.secondToPossition(seconds: 30), 3)
        XCTAssertEqual(SelectedSecond.secondToPossition(seconds: 60), 4)
    }

    func testUnknownDelayFallsBackToTheFirstPopupPosition() {
        XCTAssertEqual(SelectedSecond.secondToPossition(seconds: 0), 0)
        XCTAssertEqual(SelectedSecond.secondToPossition(seconds: 7.5), 0)
    }
}
