import AppKit
import XCTest
@testable import Hideout

@MainActor
final class AboutViewControllerTests: XCTestCase {
    func testAboutViewLoadsWithoutInvalidConstraints() {
        let viewController = AboutViewController()

        viewController.loadViewIfNeeded()

        XCTAssertTrue(viewController.isViewLoaded)
    }
}
