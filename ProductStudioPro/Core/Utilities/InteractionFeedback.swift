import SwiftUI
import UIKit

// MARK: - Haptics

enum InteractionHaptics {
    /// Reads the same UserDefaults key as `CaptureSessionStore.vibrateEnabled` so button styles
    /// never need `@EnvironmentObject` (menus/popovers can omit it and must not crash).
    static var vibrateEnabledFromSettings: Bool {
        if UserDefaults.standard.object(forKey: "vibrateEnabled") == nil { return true }
        return UserDefaults.standard.bool(forKey: "vibrateEnabled")
    }

    static func tap(vibrate: Bool = true) {
        guard vibrate else { return }
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred(intensity: 0.85)
    }

    /// Prefer Settings → Vibrate without requiring an environment object.
    static func tapPreferringSettings() {
        tap(vibrate: vibrateEnabledFromSettings)
    }

    static func selection(vibrate: Bool = true) {
        guard vibrate else { return }
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    static func success(vibrate: Bool = true) {
        guard vibrate else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }

    static func warning(vibrate: Bool = true) {
        guard vibrate else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.warning)
    }

    static func error(vibrate: Bool = true) {
        guard vibrate else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.error)
    }
}

/// Runs haptic + press-visible delay before navigation / sheet work so the tap always feels registered.
enum TapFeedback {
    @MainActor
    static func run(vibrate: Bool = InteractionHaptics.vibrateEnabledFromSettings, _ action: @escaping () -> Void) {
        InteractionHaptics.tap(vibrate: vibrate)
        deferAction(action)
    }

    /// Delay only — use when `FeedbackPressButtonStyle` already fired the haptic on press-down.
    @MainActor
    static func deferAction(_ action: @escaping () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: DS.Motion.tapActionDelayNanoseconds)
            action()
        }
    }
}

// MARK: - Press animation (Apple-style spring scale)

struct FeedbackPressButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = DS.Motion.pressScaleIcon
    var playsHaptic: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        FeedbackPressButtonStyleBody(
            configuration: configuration,
            pressedScale: pressedScale,
            playsHaptic: playsHaptic,
            vibrate: InteractionHaptics.vibrateEnabledFromSettings
        )
    }
}

private struct FeedbackPressButtonStyleBody: View {
    let configuration: ButtonStyleConfiguration
    let pressedScale: CGFloat
    let playsHaptic: Bool
    let vibrate: Bool

    var body: some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .opacity(configuration.isPressed ? DS.Motion.pressedOpacity : 1)
            .brightness(configuration.isPressed ? DS.Motion.pressedBrightness : 0)
            .animation(DS.Motion.pressSpring, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed, playsHaptic { InteractionHaptics.tap(vibrate: vibrate) }
            }
    }
}

extension ButtonStyle where Self == FeedbackPressButtonStyle {
    static var feedbackPress: FeedbackPressButtonStyle { FeedbackPressButtonStyle() }
}

// MARK: - Toolbar icon button (bounce symbol + haptic + disabled state)

struct FeedbackIconButton: View {
    let systemName: String
    var side: CGFloat = 38
    var symbolSize: CGFloat = 17
    var isEnabled: Bool = true
    var accessibilityLabel: String?
    let action: () -> Void

    @State private var bounceTrigger = 0

    var body: some View {
        Button {
            guard isEnabled else { return }
            bounceTrigger += 1
            TapFeedback.run { action() }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: symbolSize, weight: .medium))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(isEnabled ? DS.ColorToken.accent : DS.ColorToken.tertiaryLabel)
                .symbolEffect(.bounce, value: bounceTrigger)
                .previewToolbarIconSlot(side: side)
        }
        .buttonStyle(FeedbackPressButtonStyle(playsHaptic: false))
        .disabled(!isEnabled)
        .allowsHitTesting(isEnabled)
        .opacity(isEnabled ? 1 : DS.Motion.disabledOpacity)
        .saturation(isEnabled ? 1 : DS.Motion.disabledSaturation)
        .accessibilityLabel(accessibilityLabel ?? systemName)
        .accessibilityAddTraits(isEnabled ? [] : .isStaticText)
    }
}

// MARK: - Preview dock icon row (Share, Edit, Background, …)

struct FeedbackDockButton: View {
    let systemName: String
    let label: String
    var isEnabled: Bool = true
    var isDestructive: Bool = false
    let action: () -> Void

    @State private var bounceTrigger = 0

    private var foreground: Color {
        guard isEnabled else { return DS.ColorToken.tertiaryLabel }
        return isDestructive ? DS.ColorToken.error : DS.ColorToken.label
    }

    var body: some View {
        Button {
            guard isEnabled else { return }
            bounceTrigger += 1
            TapFeedback.run { action() }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: systemName)
                    .font(DS.TypeScale.sectionTitle.weight(.medium))
                    .symbolEffect(.bounce, value: bounceTrigger)
                Text(label)
                    .font(DS.TypeScale.micro.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .truncationMode(.tail)
                    .allowsTightening(true)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(foreground)
            .padding(.vertical, 4)
        }
        .buttonStyle(FeedbackPressButtonStyle(pressedScale: DS.Motion.pressScaleCompact, playsHaptic: false))
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
        .disabled(!isEnabled)
        .allowsHitTesting(isEnabled)
        .opacity(isEnabled ? 1 : DS.Motion.disabledOpacity)
        .saturation(isEnabled ? 1 : DS.Motion.disabledSaturation)
        .accessibilityLabel(label)
    }
}

// MARK: - Loading state

@MainActor
final class LoadingStateManager: ObservableObject {
    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let isError: Bool
    }

    struct GlobalTask: Equatable {
        let id = UUID()
        var message: String
        var progress: Double?
    }

    @Published private(set) var globalTask: GlobalTask?
    @Published private(set) var inlineMessage: String?
    @Published var toast: Toast?
    /// Published so UI (e.g. Queue “Exporting…”) refreshes when actions start/end.
    @Published private(set) var runningActionKeys: Set<String> = []

    private var inlineDepth = 0
    private var globalDepth = 0

    func isRunning(_ key: String) -> Bool {
        runningActionKeys.contains(key)
    }

    func isAnyRunning(prefix: String) -> Bool {
        runningActionKeys.contains { $0.hasPrefix(prefix) }
    }

    func pushGlobal(_ message: String, progress: Double? = nil) {
        globalDepth += 1
        globalTask = GlobalTask(message: message, progress: progress)
        InteractionHUDController.shared.refreshHitTesting()
    }

    func popGlobal() {
        globalDepth = max(0, globalDepth - 1)
        if globalDepth == 0 { globalTask = nil }
        InteractionHUDController.shared.refreshHitTesting()
    }

    func pushInline(_ message: String) {
        inlineDepth += 1
        inlineMessage = message
    }

    func popInline() {
        inlineDepth = max(0, inlineDepth - 1)
        if inlineDepth == 0 { inlineMessage = nil }
    }

    /// Clears matching action keys and any leftover “Exporting…” global overlay (share cancel safety).
    @MainActor
    func endActions(prefix: String) {
        let matching = runningActionKeys.filter { $0.hasPrefix(prefix) }
        if !matching.isEmpty {
            runningActionKeys.subtract(matching)
        }
        if let message = globalTask?.message,
           message.localizedCaseInsensitiveContains("exporting") {
            globalDepth = 0
            globalTask = nil
            InteractionHUDController.shared.refreshHitTesting()
        }
    }

    func showToast(_ message: String, isError: Bool = false) {
        toast = Toast(message: message, isError: isError)
        Task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            if toast?.message == message { toast = nil }
        }
    }

    @discardableResult
    func runAction(
        key: String,
        message: String,
        global: Bool = false,
        hapticOnStart: Bool = true,
        vibrate: Bool = true,
        operation: @escaping () async throws -> Void
    ) -> Task<Void, Never> {
        guard !runningActionKeys.contains(key) else { return Task {} }
        runningActionKeys.insert(key)
        if hapticOnStart { InteractionHaptics.tap(vibrate: vibrate) }

        return Task {
            // Coordinate delayed loading on MainActor and await settlement after cancel so
            // pushGlobal cannot land after we already popped / cleared the key.
            let loadingGate = LoadingPresentationGate()
            let loadingTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 280_000_000)
                guard !Task.isCancelled else { return }
                loadingGate.showed = true
                if global { pushGlobal(message) } else { pushInline(message) }
            }

            do {
                try await operation()
                await MainActor.run { InteractionHaptics.success(vibrate: vibrate) }
            } catch {
                await MainActor.run {
                    InteractionHaptics.error(vibrate: vibrate)
                    showToast(error.localizedDescription, isError: true)
                }
            }

            loadingTask.cancel()
            _ = await loadingTask.result
            await MainActor.run {
                if loadingGate.showed {
                    if global { popGlobal() } else { popInline() }
                }
                runningActionKeys.remove(key)
            }
        }
    }
}

/// Shared flag for delayed loading presentation (MainActor-only writes).
private final class LoadingPresentationGate: @unchecked Sendable {
    @MainActor var showed = false
}

private struct LoadingStateManagerKey: EnvironmentKey {
    static let defaultValue: LoadingStateManager? = nil
}

extension EnvironmentValues {
    var loadingState: LoadingStateManager? {
        get { self[LoadingStateManagerKey.self] }
        set { self[LoadingStateManagerKey.self] = newValue }
    }
}

// MARK: - HUD window (above all sheets)

@MainActor
final class InteractionHUDController {
    static let shared = InteractionHUDController()

    private var hudWindow: InteractionPassthroughWindow?
    private weak var session: CaptureSessionStore?
    private weak var loadingState: LoadingStateManager?

    private init() {}

    func install(session: CaptureSessionStore, loadingState: LoadingStateManager) {
        self.session = session
        self.loadingState = loadingState
        AppOperationalAlerts.install(loadingState: loadingState)
        guard hudWindow == nil, let scene = activeWindowScene() else {
            refreshHitTesting()
            return
        }

        let window = InteractionPassthroughWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear

        let root = InteractionHUDOverlay()
            .environmentObject(session)
            .environment(\.loadingState, loadingState)

        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        window.rootViewController = host
        window.isHidden = false
        hudWindow = window
        refreshHitTesting()
    }

    func refreshHitTesting() {
        hudWindow?.blocksInteraction = shouldBlockInteraction
    }

    /// Surfaces operational failures (disk / Vision) above sheets.
    func showErrorToast(_ message: String) {
        loadingState?.showToast(message, isError: true)
        InteractionHaptics.error()
    }

    private var shouldBlockInteraction: Bool {
        guard let session else { return false }
        if session.activeImport != nil { return true }
        if session.blockingOperationDepth > 0 { return true }
        if loadingState?.globalTask != nil { return true }
        // Apply / main-canvas matching / draft busy — block taps while HUD shows.
        if session.showsMagicPreviewOverlay { return true }
        return false
    }

    private func activeWindowScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    }
}

private final class InteractionPassthroughWindow: UIWindow {
    var blocksInteraction = false

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard blocksInteraction else { return nil }
        return super.hitTest(point, with: event)
    }
}

/// Mounts the HUD window once the app scene is active.
struct InteractionHUDInstaller: View {
    @ObservedObject var session: CaptureSessionStore
    @ObservedObject var loadingState: LoadingStateManager

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                InteractionHUDController.shared.install(session: session, loadingState: loadingState)
            }
            .onChange(of: session.blockingOperationDepth) { _, _ in
                InteractionHUDController.shared.refreshHitTesting()
            }
            .onChange(of: session.showsMagicPreviewOverlay) { _, _ in
                InteractionHUDController.shared.refreshHitTesting()
            }
            .onChange(of: session.activeImport?.total) { _, _ in
                InteractionHUDController.shared.refreshHitTesting()
            }
            .onChange(of: loadingState.globalTask?.message) { _, _ in
                InteractionHUDController.shared.refreshHitTesting()
            }
    }
}

// MARK: - Global overlay + toast (HUD content)

struct InteractionHUDOverlay: View {
    @EnvironmentObject private var session: CaptureSessionStore
    @Environment(\.loadingState) private var loadingState

    var body: some View {
        ZStack {
            if let imp = session.activeImport {
                MagicPreviewOverlayHost(
                    isApplying: false,
                    message: "Importing photos \(imp.completed)/\(imp.total)",
                    subtitle: imp.message,
                    progress: Double(imp.completed) / Double(max(1, imp.total))
                )
            } else if session.blockingOperationDepth > 0 {
                MagicPreviewOverlayHost(
                    isApplying: true,
                    message: session.blockingOperationMessage,
                    compact: true
                )
            } else if let task = loadingState?.globalTask {
                MagicPreviewOverlayHost(
                    isApplying: true,
                    message: task.message,
                    progress: task.progress,
                    compact: true
                )
            } else if session.showsMagicPreviewOverlay {
                MagicPreviewOverlayHost(
                    isApplying: session.magicPreviewOverlayApplying,
                    message: session.magicPreviewOverlayMessage
                )
            }

            if let toast = loadingState?.toast {
                VStack {
                    Spacer()
                    InteractionToastView(message: toast.message, isError: toast.isError)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 28)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(.spring(response: 0.34, dampingFraction: 0.86), value: toast.id)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .allowsHitTesting(
            session.activeImport != nil
                || session.blockingOperationDepth > 0
                || loadingState?.globalTask != nil
                || session.showsMagicPreviewOverlay
        )
        .onAppear { InteractionHUDController.shared.refreshHitTesting() }
    }
}

/// Legacy name — routes to HUD overlay for in-view embedding when needed.
struct GlobalLoadingOverlay: View {
    var body: some View {
        InteractionHUDOverlay()
    }
}

struct InteractionToastView: View {
    let message: String
    var isError: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isError ? AppTheme.error : AppTheme.success)
            Text(message)
                .font(DS.TypeScale.caption)
                .foregroundStyle(DS.ColorToken.label)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(DS.ColorToken.separator, lineWidth: 1))
        .shadow(color: DS.ColorToken.elevatedShadow, radius: 8, y: 3)
    }
}

struct InlineLoadingBadge: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.85)
            Text(message)
                .font(DS.TypeScale.caption)
                .foregroundStyle(DS.ColorToken.secondaryLabel)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

// MARK: - Async action button

enum AsyncActionChrome {
    case bare
    case primary
    case secondary
}

struct AsyncActionButton<Label: View>: View {
    @Environment(\.loadingState) private var loadingState

    let key: String
    let message: String
    var global: Bool = false
    var disabled: Bool = false
    var chrome: AsyncActionChrome = .bare
    let action: () async throws -> Void
    @ViewBuilder let label: () -> Label

    @State private var isRunning = false

    var body: some View {
        Button {
            guard !isRunning, !disabled else { return }
            isRunning = true

            let vibrate = InteractionHaptics.vibrateEnabledFromSettings
            let task: Task<Void, Never>
            if let loadingState {
                task = loadingState.runAction(
                    key: key,
                    message: message,
                    global: global,
                    hapticOnStart: chrome == .bare,
                    vibrate: vibrate,
                    operation: action
                )
            } else {
                if chrome == .bare {
                    InteractionHaptics.tap(vibrate: vibrate)
                }
                task = Task {
                    defer { Task { @MainActor in isRunning = false } }
                    try? await action()
                }
            }

            Task {
                await task.value
                await MainActor.run { isRunning = false }
            }
        } label: {
            HStack(spacing: 8) {
                if isRunning {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(chrome == .primary ? DS.ColorToken.onAccent : DS.ColorToken.label)
                        .scaleEffect(0.85)
                }
                label()
            }
            .frame(maxWidth: chrome == .bare ? nil : .infinity)
        }
        .modifier(AsyncActionChromeModifier(chrome: chrome))
        .disabled(disabled || isRunning)
        .opacity(disabled || isRunning ? DS.Motion.disabledOpacity : 1)
        .saturation(disabled || isRunning ? DS.Motion.disabledSaturation : 1)
    }
}

private struct AsyncActionChromeModifier: ViewModifier {
    let chrome: AsyncActionChrome

    @ViewBuilder
    func body(content: Content) -> some View {
        switch chrome {
        case .bare:
            content.buttonStyle(FeedbackPressButtonStyle(pressedScale: DS.Motion.pressScale, playsHaptic: true))
        case .primary:
            content.buttonStyle(PrimaryButtonStyle())
        case .secondary:
            content.buttonStyle(SecondaryButtonStyle())
        }
    }
}

// MARK: - View helpers

extension View {
    func withInteractionFeedback() -> some View {
        modifier(InteractionFeedbackRootModifier())
    }

    func feedbackSheet<Content: View>(
        isPresented: Binding<Bool>,
        onOpenHaptic: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        sheet(isPresented: Binding(
            get: { isPresented.wrappedValue },
            set: { newValue in
                if newValue, onOpenHaptic { InteractionHaptics.tap() }
                isPresented.wrappedValue = newValue
            }
        ), content: content)
    }

    func inlineLoadingOverlay(_ message: String?, alignment: Alignment = .center) -> some View {
        overlay(alignment: alignment) {
            if let message {
                InlineLoadingBadge(message: message)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: message)
    }
}

private struct InteractionFeedbackRootModifier: ViewModifier {
    @Environment(\.loadingState) private var loadingState

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let msg = loadingState?.inlineMessage {
                    InlineLoadingBadge(message: msg)
                        .padding(.top, 8)
                        .transition(.opacity)
                }
            }
    }
}

/// Thumbnail cell with placeholder while image loads off the main thread.
struct AsyncThumbnailImage: View {
    let url: URL?
    let fallbackImage: UIImage?
    var placeholderSystemName: String = "photo"
    var cornerRadius: CGFloat = DS.Radius.thumbnail

    @State private var image: UIImage?
    @State private var isLoading = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DS.ColorToken.backgroundTertiary)
            } else {
                Image(systemName: placeholderSystemName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(DS.ColorToken.tertiaryLabel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DS.ColorToken.backgroundTertiary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: url?.path ?? fallbackImage.map { "\($0)" }) {
            await load()
        }
    }

    private func load() async {
        if let fallbackImage {
            image = fallbackImage
            return
        }
        guard let url else { return }
        isLoading = true
        defer { isLoading = false }
        let loaded = await Task.detached(priority: .utility) {
            autoreleasepool { UIImage(contentsOfFile: url.path) }
        }.value
        image = loaded
    }
}

// MARK: - Apply / Discard pills (preview)

struct PreviewDiscardButton: View {
    var isDisabled: Bool = false
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            guard !isDisabled else { return }
            TapFeedback.run { action() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 14, weight: .semibold))
                Text("Discard")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(DS.ColorToken.label)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                Capsule()
                    .fill(DS.ColorToken.backgroundTertiary.opacity(colorScheme == .dark ? 0.92 : 1))
            }
            .overlay(
                Capsule()
                    .stroke(DS.ColorToken.separator, lineWidth: 1)
            )
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.08),
                radius: 6,
                y: 2
            )
        }
        .buttonStyle(FeedbackPressButtonStyle(pressedScale: DS.Motion.pressScaleCompact, playsHaptic: false))
        .disabled(isDisabled)
        .opacity(isDisabled ? DS.Motion.disabledOpacity : 1)
    }
}

struct PreviewApplyButton: View {
    let isApplying: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var bounceTrigger = 0

    var body: some View {
        Button {
            guard !isApplying else { return }
            bounceTrigger += 1
            TapFeedback.run { action() }
        } label: {
            HStack(spacing: 6) {
                if isApplying {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(DS.ColorToken.onAccent)
                        .scaleEffect(0.85)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .symbolEffect(.bounce, value: bounceTrigger)
                }
                Text(isApplying ? "Applying…" : "Apply")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(DS.ColorToken.onAccent)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                isApplying
                    ? DS.ColorToken.primaryButtonFill.opacity(0.72)
                    : DS.ColorToken.primaryButtonFill,
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .stroke(DS.ColorToken.separator.opacity(colorScheme == .dark ? 0.45 : 0.2), lineWidth: 1)
            )
            .shadow(
                color: DS.ColorToken.primaryButtonFill.opacity(isApplying ? 0.18 : 0.32),
                radius: 8,
                y: 3
            )
            .animation(.easeInOut(duration: 0.2), value: isApplying)
        }
        .buttonStyle(FeedbackPressButtonStyle(pressedScale: DS.Motion.pressScaleCompact, playsHaptic: false))
        .disabled(isApplying)
    }
}

// MARK: - Legacy aliases

struct PlainPressableButtonStyle: ButtonStyle {
    var playsHaptic: Bool = true
    var pressedScale: CGFloat = DS.Motion.pressScale

    func makeBody(configuration: Configuration) -> some View {
        FeedbackPressButtonStyleBody(
            configuration: configuration,
            pressedScale: pressedScale,
            playsHaptic: playsHaptic,
            vibrate: InteractionHaptics.vibrateEnabledFromSettings
        )
    }
}

extension ButtonStyle where Self == PlainPressableButtonStyle {
    static var plainPressable: PlainPressableButtonStyle { PlainPressableButtonStyle() }
}
