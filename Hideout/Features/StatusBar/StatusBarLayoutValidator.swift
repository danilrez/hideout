import CoreGraphics
import Foundation

enum StatusBarTransitionTrigger: String {
    case launch
    case menuBarButton
    case globalShortcut
    case autoHide
    case hover
    case layoutRecovery
    case systemWake

    var clearsLayoutRecoveryGate: Bool {
        switch self {
        case .menuBarButton, .globalShortcut, .systemWake:
            return true
        case .launch, .autoHide, .hover, .layoutRecovery:
            return false
        }
    }
}

enum StatusBarWakeAction: String {
    case none
    case restartLayoutWatchdog
    case restoreCollapsedState
}

struct StatusBarSleepTransition {
    private(set) var wasCollapsedBeforeSleep: Bool?

    mutating func willSleep(isCollapsed: Bool) {
        wasCollapsedBeforeSleep = isCollapsed
    }

    mutating func didWake(isCollapsed: Bool) -> StatusBarWakeAction {
        defer { wasCollapsedBeforeSleep = nil }
        guard wasCollapsedBeforeSleep == true else { return .none }
        return isCollapsed ? .restartLayoutWatchdog : .restoreCollapsedState
    }
}

struct StatusBarLayoutValidator {
    enum FailureReason: String, Equatable {
        case collapsedRegionTooNarrow
        case collapseAnchorHidden
        case collapseAnchorButtonMissing
        case collapseAnchorButtonHidden
        case collapseAnchorWindowHidden
        case collapseAnchorFrameUnavailable
        case collapseAnchorFrameInvalid
        case collapseAnchorWidthMismatch
        case chevronItemHidden
        case chevronButtonMissing
        case chevronButtonHidden
        case chevronWindowHidden
        case chevronFrameUnavailable
        case chevronFrameInvalid
        case chevronWidthMismatch
        case chevronMovedAcrossAnchor
        case chevronShiftedDuringCollapse
        case chevronReferenceUnavailable
    }

    struct Frames: Equatable {
        let arrow: CGRect
        let anchor: CGRect
    }

    struct ItemObservation {
        let isVisible: Bool
        let buttonExists: Bool
        let buttonHidden: Bool
        let windowVisible: Bool
        let length: CGFloat
        let frame: CGRect?
    }

    struct SpacerObservation {
        let isVisible: Bool
        let length: CGFloat
    }

    struct Observation {
        let isCollapsed: Bool
        let widestDisplayWidth: CGFloat
        let chevron: ItemObservation
        let collapseAnchor: ItemObservation
        let spacers: [SpacerObservation]
    }

    private(set) var referenceFrames: Frames?
    private(set) var requiresManualCollapse = false
    private(set) var pendingFailureReason: FailureReason?

    var shouldScheduleAutoHide: Bool {
        !requiresManualCollapse
    }

    private static let itemWidthTolerance: CGFloat = 1

    private static func hasValidFrame(_ frame: CGRect) -> Bool {
        frame.minX.isFinite && frame.minY.isFinite &&
            frame.maxX.isFinite && frame.maxY.isFinite &&
            frame.width.isFinite && frame.width > 0 &&
            frame.height.isFinite && frame.height > 0
    }

    static func collapseUnit(narrowestDisplayWidth: CGFloat) -> CGFloat {
        max(200, (narrowestDisplayWidth / 2 - 64).rounded(.down))
    }

    static func activeSpacerCount(
        widestDisplayWidth: CGFloat,
        collapseUnit: CGFloat,
        availableSpacers: Int
    ) -> Int {
        guard collapseUnit > 0, availableSpacers > 0 else { return 0 }
        let requiredUnits = Int(ceil(widestDisplayWidth / collapseUnit))
        return min(availableSpacers, max(0, requiredUnits - 1))
    }

    static func hasAdequateCollapsedRegion(
        requiredDisplayWidth: CGFloat,
        anchorLength: CGFloat,
        spacers: [SpacerObservation]
    ) -> Bool {
        guard requiredDisplayWidth.isFinite, requiredDisplayWidth > 0,
              anchorLength.isFinite, anchorLength > 0 else {
            return false
        }

        var regionWidth = anchorLength
        for spacer in spacers where spacer.isVisible {
            guard spacer.length.isFinite, spacer.length > 0 else { return false }
            regionWidth += spacer.length
        }
        return regionWidth.isFinite && regionWidth >= requiredDisplayWidth
    }

    static func hasExpectedItemOrder(
        arrowFrame: CGRect,
        anchorFrame: CGRect,
        isLTR: Bool
    ) -> Bool {
        // The collapsed anchor spans the hidden region, so normal chevron
        // placement may overlap its frame while preserving the correct order.
        isLTR ? arrowFrame.minX >= anchorFrame.minX : arrowFrame.minX <= anchorFrame.minX
    }

    static func hasChevronShiftedTowardAnchorBeyondTolerance(
        arrowFrame: CGRect,
        anchorFrame: CGRect,
        referenceArrowFrame: CGRect,
        referenceAnchorFrame: CGRect,
        isLTR: Bool
    ) -> Bool {
        let currentOffset = arrowFrame.minX - anchorFrame.minX
        let referenceOffset = referenceArrowFrame.minX - referenceAnchorFrame.minX
        // Only movement toward the anchor threatens the chevron's ordering.
        // Other status items can move the anchor away without making the
        // chevron less reachable.
        let driftTowardAnchor = isLTR
            ? referenceOffset - currentOffset
            : currentOffset - referenceOffset
        let toleratedDrift = max(2, arrowFrame.width / 2)
        return driftTowardAnchor > toleratedDrift
    }

    static func isChevronSeparatedFromAnchor(
        arrowFrame: CGRect,
        anchorFrame: CGRect,
        isLTR: Bool
    ) -> Bool {
        if isLTR {
            return arrowFrame.minX >= anchorFrame.maxX
        }
        return arrowFrame.maxX <= anchorFrame.minX
    }

    mutating func setReferenceFrames(_ frames: Frames?) {
        referenceFrames = frames
        if frames == nil {
            pendingFailureReason = nil
        }
    }

    mutating func stopMonitoring() {
        referenceFrames = nil
        pendingFailureReason = nil
    }

    mutating func requireManualCollapse() {
        requiresManualCollapse = true
        pendingFailureReason = nil
    }

    mutating func noteCollapseAttempt(trigger: StatusBarTransitionTrigger) {
        if trigger.clearsLayoutRecoveryGate {
            requiresManualCollapse = false
            pendingFailureReason = nil
        }
    }

    mutating func validate(
        _ observation: Observation,
        isLTR: Bool
    ) -> FailureReason? {
        guard observation.isCollapsed else {
            referenceFrames = nil
            pendingFailureReason = nil
            return nil
        }

        let reason: FailureReason?
        if !observation.collapseAnchor.isVisible {
            reason = .collapseAnchorHidden
        } else if !observation.collapseAnchor.buttonExists {
            reason = .collapseAnchorButtonMissing
        } else if observation.collapseAnchor.buttonHidden {
            reason = .collapseAnchorButtonHidden
        } else if !observation.collapseAnchor.windowVisible {
            reason = .collapseAnchorWindowHidden
        } else if observation.collapseAnchor.frame == nil {
            reason = .collapseAnchorFrameUnavailable
        } else if let anchorFrame = observation.collapseAnchor.frame,
                  !Self.hasValidFrame(anchorFrame) {
            reason = .collapseAnchorFrameInvalid
        } else if let anchorFrame = observation.collapseAnchor.frame,
                  !observation.collapseAnchor.length.isFinite || observation.collapseAnchor.length <= 0 ||
                  abs(anchorFrame.width - observation.collapseAnchor.length) > Self.itemWidthTolerance {
            reason = .collapseAnchorWidthMismatch
        } else if !observation.chevron.isVisible {
            reason = .chevronItemHidden
        } else if !observation.chevron.buttonExists {
            reason = .chevronButtonMissing
        } else if observation.chevron.buttonHidden {
            reason = .chevronButtonHidden
        } else if !observation.chevron.windowVisible {
            reason = .chevronWindowHidden
        } else if observation.chevron.frame == nil {
            reason = .chevronFrameUnavailable
        } else if let arrowFrame = observation.chevron.frame,
                  !Self.hasValidFrame(arrowFrame) {
            reason = .chevronFrameInvalid
        } else if !Self.hasAdequateCollapsedRegion(
            requiredDisplayWidth: observation.widestDisplayWidth,
            anchorLength: observation.collapseAnchor.length,
            spacers: observation.spacers
        ) {
            reason = .collapsedRegionTooNarrow
        } else if let arrowFrame = observation.chevron.frame,
                  !observation.chevron.length.isFinite || observation.chevron.length <= 0 ||
                  abs(arrowFrame.width - observation.chevron.length) > Self.itemWidthTolerance {
            reason = .chevronWidthMismatch
        } else if let arrowFrame = observation.chevron.frame,
                  let anchorFrame = observation.collapseAnchor.frame,
                  !Self.hasExpectedItemOrder(
                    arrowFrame: arrowFrame,
                    anchorFrame: anchorFrame,
                    isLTR: isLTR
                  ) {
            reason = .chevronMovedAcrossAnchor
        } else if let arrowFrame = observation.chevron.frame,
                  let anchorFrame = observation.collapseAnchor.frame,
                  let referenceFrames,
                  Self.hasChevronShiftedTowardAnchorBeyondTolerance(
                    arrowFrame: arrowFrame,
                    anchorFrame: anchorFrame,
                    referenceArrowFrame: referenceFrames.arrow,
                    referenceAnchorFrame: referenceFrames.anchor,
                    isLTR: isLTR
                  ) {
            reason = .chevronShiftedDuringCollapse
        } else if referenceFrames == nil {
            reason = .chevronReferenceUnavailable
        } else {
            reason = nil
        }

        if let reason {
            // A transient AppKit frame can briefly put the chevron across the
            // anchor while the menu bar is rearranging. The controller checks
            // again after a short settle delay before starting recovery.
            if pendingFailureReason != nil {
                requiresManualCollapse = true
            }
            pendingFailureReason = reason
        } else {
            pendingFailureReason = nil
        }
        return reason
    }
}
