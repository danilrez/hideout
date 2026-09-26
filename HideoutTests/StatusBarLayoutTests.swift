import CoreGraphics
import AppKit
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

    @MainActor
    func testGlyphFollowsDetectedDirectionAfterButtonExpands() {
        let button = NSView(frame: NSRect(x: 0, y: 0, width: 24, height: 22))
        let glyph = NSView()
        button.addSubview(glyph)
        glyph.translatesAutoresizingMaskIntoConstraints = false
        var edgeConstraint: NSLayoutConstraint?

        NSLayoutConstraint.activate([
            glyph.widthAnchor.constraint(equalToConstant: 16),
            glyph.heightAnchor.constraint(equalToConstant: 16),
            glyph.centerYAnchor.constraint(equalTo: button.centerYAnchor)
        ])
        StatusBarGlyphLayout.updateEdgeConstraint(
            &edgeConstraint,
            glyphView: glyph,
            button: button,
            isLTR: false,
            inset: 3
        )
        button.layoutSubtreeIfNeeded()
        XCTAssertEqual(glyph.frame.minX, 3, accuracy: 0.5)

        button.setFrameSize(NSSize(width: 836, height: 22))
        button.layoutSubtreeIfNeeded()
        XCTAssertEqual(glyph.frame.minX, 3, accuracy: 0.5)

        StatusBarGlyphLayout.updateEdgeConstraint(
            &edgeConstraint,
            glyphView: glyph,
            button: button,
            isLTR: true,
            inset: 3
        )
        button.layoutSubtreeIfNeeded()

        XCTAssertEqual(glyph.frame.minX, 817, accuracy: 0.5)
    }
}
