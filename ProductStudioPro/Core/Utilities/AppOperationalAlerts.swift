import Foundation

/// Bridges non-UI subsystems (disk, Vision) to user-visible toasts without tight coupling.
enum AppOperationalAlerts {
    private static let lock = NSLock()
    private static weak var loadingState: LoadingStateManager?
    private static var lastMessage: String?
    private static var lastPresentedAt: Date = .distantPast
    private static let debounceInterval: TimeInterval = 2.8

    @MainActor
    static func install(loadingState: LoadingStateManager) {
        self.loadingState = loadingState
        SessionDiskStore.onOperationalFailure = { message in
            present(message)
        }
        ImageProcessor.onOperationalFailure = { message in
            present(message)
        }
    }

    static func present(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lock.lock()
        let now = Date()
        if trimmed == lastMessage, now.timeIntervalSince(lastPresentedAt) < debounceInterval {
            lock.unlock()
            return
        }
        lastMessage = trimmed
        lastPresentedAt = now
        lock.unlock()

        DispatchQueue.main.async {
            if let loadingState {
                loadingState.showToast(trimmed, isError: true)
                InteractionHaptics.error()
            } else {
                InteractionHUDController.shared.showErrorToast(trimmed)
            }
        }
    }
}
