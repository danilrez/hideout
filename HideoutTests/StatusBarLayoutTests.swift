import CoreGraphics
import AppKit
import Foundation
import XCTest
@testable import Hideout

final class StatusBarLayoutTests: XCTestCase {
    func testCollapseUnitStaysBelowTheMacOS27StatusItemCliff() {
        XCTAssertEqual(StatusBarLayoutValidator.collapseUnit(narrowestDisplayWidth: 1728), 800)
        XCTAssertEqual(StatusBarLayoutValidator.collapseUnit(narrowestDisplayWidth: 400), 200)
    }

    func testSpacerCountCoversTheWidestDisplayWithoutExceedingCapacity() {
        XCTAssertEqual(
            StatusBarLayoutValidator.activeSpacerCount(
                widestDisplayWidth: 1800,
                collapseUnit: 800,
                availableSpacers: 6
            ),
            2
        )
        XCTAssertEqual(
            StatusBarLayoutValidator.activeSpacerCount(
                widestDisplayWidth: 5800,
                collapseUnit: 800,
                availableSpacers: 6
            ),
            6
        )
    }

    func testSpacerCountIsZeroForInvalidOrEmptyInputs() {
        XCTAssertEqual(
            StatusBarLayoutValidator.activeSpacerCount(
                widestDisplayWidth: 1800,
                collapseUnit: 0,
                availableSpacers: 6
            ),
            0
        )
        XCTAssertEqual(
            StatusBarLayoutValidator.activeSpacerCount(
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
            StatusBarLayoutValidator.isChevronSeparatedFromAnchor(
                arrowFrame: CGRect(x: 120, y: 0, width: 24, height: 22),
                anchorFrame: anchor,
                isLTR: true
            )
        )
        XCTAssertFalse(
            StatusBarLayoutValidator.isChevronSeparatedFromAnchor(
                arrowFrame: CGRect(x: 119, y: 0, width: 24, height: 22),
                anchorFrame: anchor,
                isLTR: true
            )
        )
    }

    func testChevronMustBeBeforeAnchorInRTLLayout() {
        let anchor = CGRect(x: 100, y: 0, width: 20, height: 22)
        XCTAssertTrue(
            StatusBarLayoutValidator.isChevronSeparatedFromAnchor(
                arrowFrame: CGRect(x: 56, y: 0, width: 24, height: 22),
                anchorFrame: anchor,
                isLTR: false
            )
        )
        XCTAssertFalse(
            StatusBarLayoutValidator.isChevronSeparatedFromAnchor(
                arrowFrame: CGRect(x: 77, y: 0, width: 24, height: 22),
                anchorFrame: anchor,
                isLTR: false
            )
        )
    }

    func testCollapsedLayoutOrderDetectsChevronMovingAcrossAnchor() {
        let anchor = CGRect(x: 100, y: 0, width: 836, height: 22)
        XCTAssertTrue(
            StatusBarLayoutValidator.hasExpectedItemOrder(
                arrowFrame: CGRect(x: 140, y: 0, width: 24, height: 22),
                anchorFrame: anchor,
                isLTR: true
            )
        )
        XCTAssertFalse(
            StatusBarLayoutValidator.hasExpectedItemOrder(
                arrowFrame: CGRect(x: 99, y: 0, width: 24, height: 22),
                anchorFrame: anchor,
                isLTR: true
            )
        )
        XCTAssertTrue(
            StatusBarLayoutValidator.hasExpectedItemOrder(
                arrowFrame: CGRect(x: 76, y: 0, width: 24, height: 22),
                anchorFrame: anchor,
                isLTR: false
            )
        )
        XCTAssertFalse(
            StatusBarLayoutValidator.hasExpectedItemOrder(
                arrowFrame: CGRect(x: 101, y: 0, width: 24, height: 22),
                anchorFrame: anchor,
                isLTR: false
            )
        )
    }

    func testCollapsedChevronDriftTowardAnchorIsDetectedBeforeItCrossesAnchor() {
        let referenceAnchor = CGRect(x: 1352, y: 1138.5, width: 836, height: 22)
        let referenceArrow = CGRect(x: 2220, y: 1138.5, width: 24, height: 22)
        let currentArrow = CGRect(x: 2202, y: 1138.5, width: 24, height: 22)

        XCTAssertTrue(
            StatusBarLayoutValidator.hasExpectedItemOrder(
                arrowFrame: currentArrow,
                anchorFrame: referenceAnchor,
                isLTR: true
            )
        )
        XCTAssertTrue(
            StatusBarLayoutValidator.hasChevronShiftedTowardAnchorBeyondTolerance(
                arrowFrame: currentArrow,
                anchorFrame: referenceAnchor,
                referenceArrowFrame: referenceArrow,
                referenceAnchorFrame: referenceAnchor,
                isLTR: true
            )
        )
    }

    func testCollapsedChevronPositionAllowsSmallFrameJitter() {
        let anchor = CGRect(x: 1352, y: 1138.5, width: 836, height: 22)
        let referenceArrow = CGRect(x: 2220, y: 1138.5, width: 24, height: 22)

        XCTAssertFalse(
            StatusBarLayoutValidator.hasChevronShiftedTowardAnchorBeyondTolerance(
                arrowFrame: CGRect(x: 2226, y: 1138.5, width: 24, height: 22),
                anchorFrame: anchor,
                referenceArrowFrame: referenceArrow,
                referenceAnchorFrame: anchor,
                isLTR: true
            )
        )
    }

    func testLayoutValidatorAcceptsStableChevronFrames() {
        var validator = StatusBarLayoutValidator()
        validator.setReferenceFrames(referenceFrames)

        XCTAssertNil(validator.validate(healthyObservation, isLTR: true))
        XCTAssertFalse(validator.requiresManualCollapse)
        XCTAssertTrue(validator.shouldScheduleAutoHide)
    }

    func testLayoutValidatorAllowsChevronToShiftAwayFromAnchor() {
        var validator = StatusBarLayoutValidator()
        validator.setReferenceFrames(referenceFrames)

        let current = observation(
            arrowFrame: CGRect(x: 2222, y: 1138.5, width: 24, height: 22),
            anchorFrame: CGRect(x: 1326, y: 1138.5, width: 836, height: 22)
        )

        XCTAssertNil(validator.validate(current, isLTR: true))
        XCTAssertFalse(validator.requiresManualCollapse)
        XCTAssertTrue(validator.shouldScheduleAutoHide)
    }

    func testLayoutValidatorMirrorsSafeDriftForRTL() {
        var validator = StatusBarLayoutValidator()
        validator.setReferenceFrames(
            StatusBarLayoutValidator.Frames(
                arrow: CGRect(x: 1300, y: 1138.5, width: 24, height: 22),
                anchor: CGRect(x: 1352, y: 1138.5, width: 836, height: 22)
            )
        )

        XCTAssertNil(
            validator.validate(
                observation(arrowFrame: CGRect(x: 1292, y: 1138.5, width: 24, height: 22)),
                isLTR: false
            )
        )

        XCTAssertEqual(
            validator.validate(
                observation(arrowFrame: CGRect(x: 1316, y: 1138.5, width: 24, height: 22)),
                isLTR: false
            ),
            .chevronShiftedDuringCollapse
        )
    }

    func testCollapsedRegionCoverageCountsOnlyVisibleSpacers() {
        let spacers = [
            StatusBarLayoutValidator.SpacerObservation(isVisible: true, length: 800),
            StatusBarLayoutValidator.SpacerObservation(isVisible: false, length: 800)
        ]

        XCTAssertFalse(
            StatusBarLayoutValidator.hasAdequateCollapsedRegion(
                requiredDisplayWidth: 1700,
                anchorLength: 800,
                spacers: spacers
            )
        )
        XCTAssertTrue(
            StatusBarLayoutValidator.hasAdequateCollapsedRegion(
                requiredDisplayWidth: 1600,
                anchorLength: 800,
                spacers: spacers
            )
        )
    }

    func testLayoutValidatorRejectsCollapsedRegionThatDoesNotCoverWidestDisplay() {
        var validator = StatusBarLayoutValidator()
        validator.setReferenceFrames(referenceFrames)

        XCTAssertEqual(
            validator.validate(
                observation(widestDisplayWidth: 6000),
                isLTR: true
            ),
            .collapsedRegionTooNarrow
        )
        XCTAssertTrue(validator.requiresManualCollapse)
        XCTAssertFalse(validator.shouldScheduleAutoHide)
    }

    func testLayoutValidatorRejectsItemWidthMismatches() {
        var chevronValidator = StatusBarLayoutValidator()
        chevronValidator.setReferenceFrames(referenceFrames)
        XCTAssertEqual(
            chevronValidator.validate(observation(chevronLength: 36), isLTR: true),
            .chevronWidthMismatch
        )

        var anchorValidator = StatusBarLayoutValidator()
        anchorValidator.setReferenceFrames(referenceFrames)
        XCTAssertEqual(
            anchorValidator.validate(observation(collapseAnchorLength: 800), isLTR: true),
            .collapseAnchorWidthMismatch
        )
    }

    func testLayoutValidatorRequestsRecoveryForInvalidChevronLayouts() {
        let cases: [(StatusBarLayoutValidator.Observation, StatusBarLayoutValidator.FailureReason)] = [
            (observation(chevronItemVisible: false), .chevronItemHidden),
            (observation(buttonExists: false), .chevronButtonMissing),
            (observation(buttonHidden: true), .chevronButtonHidden),
            (observation(windowVisible: false), .chevronWindowHidden),
            (observation(arrowFrame: nil), .chevronFrameUnavailable),
            (
                observation(arrowFrame: CGRect(x: CGFloat.nan, y: 1138.5, width: 24, height: 22)),
                .chevronFrameInvalid
            ),
            (
                observation(anchorFrame: CGRect(x: 1352, y: 1138.5, width: CGFloat.nan, height: 22)),
                .collapseAnchorFrameInvalid
            ),
            (observation(arrowFrame: CGRect(x: 1340, y: 1138.5, width: 24, height: 22)), .chevronMovedAcrossAnchor),
            (observation(arrowFrame: CGRect(x: 2202, y: 1138.5, width: 24, height: 22)), .chevronShiftedDuringCollapse)
        ]

        for (observation, expectedReason) in cases {
            var validator = StatusBarLayoutValidator()
            validator.setReferenceFrames(referenceFrames)

            XCTAssertEqual(
                validator.validate(observation, isLTR: true),
                expectedReason,
                "Unexpected recovery reason for \(expectedReason.rawValue)"
            )
            XCTAssertTrue(validator.requiresManualCollapse)
            XCTAssertFalse(validator.shouldScheduleAutoHide)
            XCTAssertNil(validator.validate(healthyObservation, isLTR: true))
            XCTAssertTrue(validator.requiresManualCollapse)
            XCTAssertFalse(validator.shouldScheduleAutoHide)
        }
    }

    func testLayoutValidatorAcceptsChevronAtExpectedCollapsedOffset() {
        var validator = StatusBarLayoutValidator()
        let collapsedFrames = StatusBarLayoutValidator.Frames(
            arrow: CGRect(x: 1406, y: 1138.5, width: 24, height: 22),
            anchor: CGRect(x: 1370, y: 1138.5, width: 836, height: 22)
        )
        validator.setReferenceFrames(collapsedFrames)

        XCTAssertNil(
            validator.validate(
                observation(
                    arrowFrame: collapsedFrames.arrow,
                    anchorFrame: collapsedFrames.anchor
                ),
                isLTR: true
            )
        )
        XCTAssertFalse(validator.requiresManualCollapse)
        XCTAssertTrue(validator.shouldScheduleAutoHide)
    }

    func testLayoutValidatorRequiresASettledReferenceFrame() {
        var validator = StatusBarLayoutValidator()

        XCTAssertEqual(
            validator.validate(healthyObservation, isLTR: true),
            .chevronReferenceUnavailable
        )
        XCTAssertTrue(validator.requiresManualCollapse)
        XCTAssertFalse(validator.shouldScheduleAutoHide)
    }

    func testExpandedLayoutStopsMonitoringWithoutClearingRecoveryGate() {
        var validator = StatusBarLayoutValidator()
        validator.setReferenceFrames(referenceFrames)
        validator.requireManualCollapse()

        XCTAssertNil(validator.validate(observation(isCollapsed: false), isLTR: true))
        XCTAssertNil(validator.referenceFrames)
        XCTAssertTrue(validator.requiresManualCollapse)
        XCTAssertFalse(validator.shouldScheduleAutoHide)
    }

    func testExplicitUserCollapseTriggersClearRecoveryGate() {
        for trigger in [StatusBarTransitionTrigger.menuBarButton, .globalShortcut] {
            var validator = StatusBarLayoutValidator()
            validator.requireManualCollapse()

            validator.noteCollapseAttempt(trigger: trigger)

            XCTAssertFalse(validator.requiresManualCollapse, "\(trigger) should clear the recovery gate")
            XCTAssertTrue(validator.shouldScheduleAutoHide)
        }
    }

    func testAutomaticAndRecoveryCollapseTriggersKeepRecoveryGateClosed() {
        for trigger in [StatusBarTransitionTrigger.launch, .autoHide, .hover, .layoutRecovery] {
            var validator = StatusBarLayoutValidator()
            validator.requireManualCollapse()

            validator.noteCollapseAttempt(trigger: trigger)

            XCTAssertTrue(validator.requiresManualCollapse, "\(trigger) must not clear the recovery gate")
            XCTAssertFalse(validator.shouldScheduleAutoHide)
        }
    }

    func testLayoutValidatorUsesMirroredOrderForRTL() {
        var validator = StatusBarLayoutValidator()
        validator.setReferenceFrames(
            StatusBarLayoutValidator.Frames(
                arrow: CGRect(x: 1312, y: 1138.5, width: 24, height: 22),
                anchor: referenceFrames.anchor
            )
        )

        XCTAssertNil(
            validator.validate(
                observation(arrowFrame: CGRect(x: 1312, y: 1138.5, width: 24, height: 22)),
                isLTR: false
            )
        )
        XCTAssertEqual(
            validator.validate(
                observation(arrowFrame: CGRect(x: 1360, y: 1138.5, width: 24, height: 22)),
                isLTR: false
            ),
            .chevronMovedAcrossAnchor
        )
    }

    private var referenceFrames: StatusBarLayoutValidator.Frames {
        StatusBarLayoutValidator.Frames(
            arrow: CGRect(x: 2220, y: 1138.5, width: 24, height: 22),
            anchor: CGRect(x: 1352, y: 1138.5, width: 836, height: 22)
        )
    }

    private var healthyObservation: StatusBarLayoutValidator.Observation {
        observation()
    }

    private func observation(
        isCollapsed: Bool = true,
        chevronItemVisible: Bool = true,
        buttonExists: Bool = true,
        buttonHidden: Bool = false,
        windowVisible: Bool = true,
        arrowFrame: CGRect? = CGRect(x: 2220, y: 1138.5, width: 24, height: 22),
        anchorFrame: CGRect? = CGRect(x: 1352, y: 1138.5, width: 836, height: 22),
        widestDisplayWidth: CGFloat = 5800,
        collapseAnchorVisible: Bool = true,
        collapseAnchorButtonExists: Bool = true,
        collapseAnchorButtonHidden: Bool = false,
        collapseAnchorWindowVisible: Bool = true,
        collapseAnchorLength: CGFloat = 836,
        chevronLength: CGFloat = 24,
        spacers: [StatusBarLayoutValidator.SpacerObservation] = Array(
            repeating: StatusBarLayoutValidator.SpacerObservation(isVisible: true, length: 836),
            count: 6
        )
    ) -> StatusBarLayoutValidator.Observation {
        StatusBarLayoutValidator.Observation(
            isCollapsed: isCollapsed,
            widestDisplayWidth: widestDisplayWidth,
            chevron: StatusBarLayoutValidator.ItemObservation(
                isVisible: chevronItemVisible,
                buttonExists: buttonExists,
                buttonHidden: buttonHidden,
                windowVisible: windowVisible,
                length: chevronLength,
                frame: arrowFrame
            ),
            collapseAnchor: StatusBarLayoutValidator.ItemObservation(
                isVisible: collapseAnchorVisible,
                buttonExists: collapseAnchorButtonExists,
                buttonHidden: collapseAnchorButtonHidden,
                windowVisible: collapseAnchorWindowVisible,
                length: collapseAnchorLength,
                frame: anchorFrame
            ),
            spacers: spacers
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
