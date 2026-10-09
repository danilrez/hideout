import CoreGraphics
import AppKit
import Foundation
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

    func testChevronMustBeAfterAnchorInLTRLayout() {
        let anchor = CGRect(x: 100, y: 0, width: 20, height: 22)
        XCTAssertTrue(
            StatusBarLayout.isChevronSeparatedFromAnchor(
                arrowFrame: CGRect(x: 120, y: 0, width: 24, height: 22),
                anchorFrame: anchor,
                isLTR: true
            )
        )
        XCTAssertFalse(
            StatusBarLayout.isChevronSeparatedFromAnchor(
                arrowFrame: CGRect(x: 119, y: 0, width: 24, height: 22),
                anchorFrame: anchor,
                isLTR: true
            )
        )
    }

    func testChevronMustBeBeforeAnchorInRTLLayout() {
        let anchor = CGRect(x: 100, y: 0, width: 20, height: 22)
        XCTAssertTrue(
            StatusBarLayout.isChevronSeparatedFromAnchor(
                arrowFrame: CGRect(x: 56, y: 0, width: 24, height: 22),
                anchorFrame: anchor,
                isLTR: false
            )
        )
        XCTAssertFalse(
            StatusBarLayout.isChevronSeparatedFromAnchor(
                arrowFrame: CGRect(x: 77, y: 0, width: 24, height: 22),
                anchorFrame: anchor,
                isLTR: false
            )
        )
    }

    func testCollapsedLayoutOrderDetectsChevronMovingAcrossAnchor() {
        let anchor = CGRect(x: 100, y: 0, width: 836, height: 22)
        XCTAssertTrue(
            StatusBarLayout.hasExpectedItemOrder(
                arrowFrame: CGRect(x: 140, y: 0, width: 24, height: 22),
                anchorFrame: anchor,
                isLTR: true
            )
        )
        XCTAssertFalse(
            StatusBarLayout.hasExpectedItemOrder(
                arrowFrame: CGRect(x: 99, y: 0, width: 24, height: 22),
                anchorFrame: anchor,
                isLTR: true
            )
        )
        XCTAssertTrue(
            StatusBarLayout.hasExpectedItemOrder(
                arrowFrame: CGRect(x: 76, y: 0, width: 24, height: 22),
                anchorFrame: anchor,
                isLTR: false
            )
        )
        XCTAssertFalse(
            StatusBarLayout.hasExpectedItemOrder(
                arrowFrame: CGRect(x: 101, y: 0, width: 24, height: 22),
                anchorFrame: anchor,
                isLTR: false
            )
        )
    }

    func testCollapsedChevronDriftIsDetectedBeforeItCrossesAnchor() {
        let referenceAnchor = CGRect(x: 1352, y: 1138.5, width: 836, height: 22)
        let referenceArrow = CGRect(x: 1388, y: 1138.5, width: 24, height: 22)
        let currentArrow = CGRect(x: 1374, y: 1138.5, width: 24, height: 22)

        XCTAssertTrue(
            StatusBarLayout.hasExpectedItemOrder(
                arrowFrame: currentArrow,
                anchorFrame: referenceAnchor,
                isLTR: true
            )
        )
        XCTAssertFalse(
            StatusBarLayout.hasChevronMaintainedOffsetFromAnchor(
                arrowFrame: currentArrow,
                anchorFrame: referenceAnchor,
                referenceArrowFrame: referenceArrow,
                referenceAnchorFrame: referenceAnchor
            )
        )
    }

    func testCollapsedChevronPositionAllowsSmallFrameJitter() {
        let anchor = CGRect(x: 1352, y: 1138.5, width: 836, height: 22)
        let referenceArrow = CGRect(x: 1388, y: 1138.5, width: 24, height: 22)

        XCTAssertTrue(
            StatusBarLayout.hasChevronMaintainedOffsetFromAnchor(
                arrowFrame: CGRect(x: 1394, y: 1138.5, width: 24, height: 22),
                anchorFrame: anchor,
                referenceArrowFrame: referenceArrow,
                referenceAnchorFrame: anchor
            )
        )
    }

    func testCollapsedLayoutWatchdogAcceptsStableChevronFrames() {
        var watchdog = StatusBarLayoutWatchdog()
        watchdog.setReferenceFrames(referenceFrames)

        XCTAssertNil(watchdog.failureReason(for: healthyObservation, isLTR: true))
        XCTAssertFalse(watchdog.requiresManualCollapse)
        XCTAssertTrue(watchdog.shouldScheduleAutoHide)
    }

    func testCollapsedLayoutWatchdogRequestsRecoveryForInvalidLayouts() {
        let cases: [(StatusBarLayoutWatchdog.Observation, StatusBarLayoutWatchdog.FailureReason)] = [
            (observation(chevronItemVisible: false), .chevronItemHidden),
            (observation(buttonExists: false), .chevronButtonMissing),
            (observation(buttonHidden: true), .chevronButtonHidden),
            (observation(windowVisible: false), .chevronWindowHidden),
            (observation(arrowFrame: nil), .chevronFrameUnavailable),
            (observation(arrowFrame: CGRect(x: 1340, y: 1138.5, width: 24, height: 22)), .chevronMovedAcrossAnchor),
            (observation(arrowFrame: CGRect(x: 1374, y: 1138.5, width: 24, height: 22)), .chevronShiftedDuringCollapse)
        ]

        for (observation, expectedReason) in cases {
            var watchdog = StatusBarLayoutWatchdog()
            watchdog.setReferenceFrames(referenceFrames)

            XCTAssertEqual(
                watchdog.failureReason(for: observation, isLTR: true),
                expectedReason,
                "Unexpected recovery reason for \(expectedReason.rawValue)"
            )
            XCTAssertTrue(watchdog.requiresManualCollapse)
            XCTAssertFalse(watchdog.shouldScheduleAutoHide)
            XCTAssertNil(watchdog.failureReason(for: healthyObservation, isLTR: true))
            XCTAssertTrue(watchdog.requiresManualCollapse)
            XCTAssertFalse(watchdog.shouldScheduleAutoHide)
        }
    }

    func testCollapsedLayoutWatchdogRequiresASettledReferenceFrame() {
        var watchdog = StatusBarLayoutWatchdog()

        XCTAssertEqual(
            watchdog.failureReason(for: healthyObservation, isLTR: true),
            .chevronReferenceUnavailable
        )
        XCTAssertTrue(watchdog.requiresManualCollapse)
        XCTAssertFalse(watchdog.shouldScheduleAutoHide)
    }

    func testExpandedLayoutStopsMonitoringWithoutClearingRecoveryGate() {
        var watchdog = StatusBarLayoutWatchdog()
        watchdog.setReferenceFrames(referenceFrames)
        watchdog.requireManualCollapse()

        XCTAssertNil(
            watchdog.failureReason(for: observation(isCollapsed: false), isLTR: true)
        )
        XCTAssertNil(watchdog.referenceFrames)
        XCTAssertTrue(watchdog.requiresManualCollapse)
        XCTAssertFalse(watchdog.shouldScheduleAutoHide)
    }

    func testExplicitUserCollapseTriggersClearRecoveryGate() {
        for trigger in [StatusBarTransitionTrigger.menuBarButton, .globalShortcut] {
            var watchdog = StatusBarLayoutWatchdog()
            watchdog.requireManualCollapse()

            watchdog.noteCollapseAttempt(trigger: trigger)

            XCTAssertFalse(watchdog.requiresManualCollapse, "\(trigger) should clear the recovery gate")
            XCTAssertTrue(watchdog.shouldScheduleAutoHide)
        }
    }

    func testAutomaticAndRecoveryCollapseTriggersKeepRecoveryGateClosed() {
        for trigger in [StatusBarTransitionTrigger.launch, .autoHide, .hover, .layoutRecovery] {
            var watchdog = StatusBarLayoutWatchdog()
            watchdog.requireManualCollapse()

            watchdog.noteCollapseAttempt(trigger: trigger)

            XCTAssertTrue(watchdog.requiresManualCollapse, "\(trigger) must not clear the recovery gate")
            XCTAssertFalse(watchdog.shouldScheduleAutoHide)
        }
    }

    func testCollapsedLayoutWatchdogUsesMirroredOrderForRTL() {
        var watchdog = StatusBarLayoutWatchdog()
        watchdog.setReferenceFrames(
            StatusBarLayoutWatchdog.Frames(
                arrow: CGRect(x: 1312, y: 1138.5, width: 24, height: 22),
                anchor: referenceFrames.anchor
            )
        )

        XCTAssertNil(
            watchdog.failureReason(
                for: observation(
                    arrowFrame: CGRect(x: 1312, y: 1138.5, width: 24, height: 22)
                ),
                isLTR: false
            )
        )
        XCTAssertEqual(
            watchdog.failureReason(
                for: observation(
                    arrowFrame: CGRect(x: 1360, y: 1138.5, width: 24, height: 22)
                ),
                isLTR: false
            ),
            .chevronMovedAcrossAnchor
        )
    }

    private var referenceFrames: StatusBarLayoutWatchdog.Frames {
        StatusBarLayoutWatchdog.Frames(
            arrow: CGRect(x: 1388, y: 1138.5, width: 24, height: 22),
            anchor: CGRect(x: 1352, y: 1138.5, width: 836, height: 22)
        )
    }

    private var healthyObservation: StatusBarLayoutWatchdog.Observation {
        observation()
    }

    private func observation(
        isCollapsed: Bool = true,
        chevronItemVisible: Bool = true,
        buttonExists: Bool = true,
        buttonHidden: Bool = false,
        windowVisible: Bool = true,
        arrowFrame: CGRect? = CGRect(x: 1388, y: 1138.5, width: 24, height: 22),
        anchorFrame: CGRect? = CGRect(x: 1352, y: 1138.5, width: 836, height: 22)
    ) -> StatusBarLayoutWatchdog.Observation {
        StatusBarLayoutWatchdog.Observation(
            isCollapsed: isCollapsed,
            chevronItemVisible: chevronItemVisible,
            buttonExists: buttonExists,
            buttonHidden: buttonHidden,
            windowVisible: windowVisible,
            arrowFrame: arrowFrame,
            anchorFrame: anchorFrame
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

#if HIDEOUT_DIAGNOSTICS
    @MainActor
    func testDiagnosticsRequireBooleanTrueFlag() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HideoutDiagnosticsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let configurationURL = directory.appendingPathComponent("config.json")
        XCTAssertFalse(HideoutDiagnostics.configurationFileEnablesDiagnostics(at: configurationURL))

        try Data("{}".utf8).write(to: configurationURL)
        XCTAssertFalse(HideoutDiagnostics.configurationFileEnablesDiagnostics(at: configurationURL))

        try Data(#"{"debug":"enabled"}"#.utf8).write(to: configurationURL)
        XCTAssertFalse(HideoutDiagnostics.configurationFileEnablesDiagnostics(at: configurationURL))

        try Data(#"{"debug":"true"}"#.utf8).write(to: configurationURL)
        XCTAssertFalse(HideoutDiagnostics.configurationFileEnablesDiagnostics(at: configurationURL))

        try Data(#"{"debug":true}"#.utf8).write(to: configurationURL)
        XCTAssertTrue(HideoutDiagnostics.configurationFileEnablesDiagnostics(at: configurationURL))

        try Data(#"{"debug":false}"#.utf8).write(to: configurationURL)
        XCTAssertFalse(HideoutDiagnostics.configurationFileEnablesDiagnostics(at: configurationURL))

        try Data(#"{"debug":1}"#.utf8).write(to: configurationURL)
        XCTAssertFalse(HideoutDiagnostics.configurationFileEnablesDiagnostics(at: configurationURL))
    }
#endif
}
