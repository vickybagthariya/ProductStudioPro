import Foundation
import SwiftUI

// MARK: - Workflow kind

enum CaptureWorkflowKind: String, CaseIterable, Identifiable {
    case standardCapture
    case multiAngle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standardCapture: return "Standard Capture"
        case .multiAngle: return "Multi-Angle Capture"
        }
    }

    var subtitle: String {
        switch self {
        case .standardCapture: return "Photograph one product or many in a session"
        case .multiAngle: return "Front, back, and side angles"
        }
    }

    var systemImage: String {
        switch self {
        case .standardCapture: return PSDesignIcons.capture
        case .multiAngle: return "camera.viewfinder"
        }
    }
}

// MARK: - Guided workflow steps

enum CaptureGuidedStep: Int, CaseIterable, Identifiable {
    case chooseWorkflow = 0
    case capturePhotos = 1
    case identifyProduct = 2
    case addToQueue = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .chooseWorkflow: return "Choose Workflow"
        case .capturePhotos: return "Capture Photos"
        case .identifyProduct: return "Identify Product"
        case .addToQueue: return "Add to Queue"
        }
    }

    var shortTitle: String {
        switch self {
        case .chooseWorkflow: return "Workflow"
        case .capturePhotos: return "Capture"
        case .identifyProduct: return "Identify"
        case .addToQueue: return "Queue"
        }
    }
}

// MARK: - Step resolution

struct CaptureStepContext {
    let hasConfirmedWorkflow: Bool
    let showsIdentification: Bool
    let isReadyToQueue: Bool

    var currentStep: CaptureGuidedStep {
        if !hasConfirmedWorkflow { return .chooseWorkflow }
        if !showsIdentification { return .capturePhotos }
        if !isReadyToQueue { return .identifyProduct }
        return .addToQueue
    }

    func isCompleted(_ step: CaptureGuidedStep) -> Bool {
        step.rawValue < currentStep.rawValue
    }

    func isActive(_ step: CaptureGuidedStep) -> Bool {
        step == currentStep
    }
}
