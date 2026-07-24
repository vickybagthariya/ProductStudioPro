import SwiftUI

@main
struct ProductStudioProApp: App {
    @StateObject private var session = CaptureSessionStore()
    @StateObject private var loadingState = LoadingStateManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            SplashAnimationView {
                HomeView()
                    .environmentObject(session)
                    .environment(\.loadingState, loadingState)
                    .withInteractionFeedback()
                    .background {
                        InteractionHUDInstaller(session: session, loadingState: loadingState)
                    }
                    .sheet(item: $session.memoryGuidance) { guidance in
                        MemoryGuidanceSheet(
                            snapshot: guidance.snapshot,
                            isBlocking: guidance.isBlocking,
                            onGoToQueue: {
                                session.dismissMemoryGuidance()
                                session.navigationPath = NavigationPath()
                                session.navigationPath.append(AppRoute.queue)
                            },
                            onManageSessions: {
                                session.dismissMemoryGuidance()
                                session.goHome()
                            }
                        )
                        .environmentObject(session)
                    }
            }
            .tint(DS.ColorToken.accent)
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    session.flushPersistenceToDisk()
                } else if phase == .active {
                    InteractionHUDController.shared.install(session: session, loadingState: loadingState)
                    session.refreshMemoryPressure()
                }
            }
        }
    }
}
