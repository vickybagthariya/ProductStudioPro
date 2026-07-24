import SwiftUI
import UIKit

// MARK: - Configuration

enum DSDropdownConfiguration {
    static let maxVisibleHeight: CGFloat = 520
    static let rowHeight: CGFloat = 44
    static let rowHorizontalPadding: CGFloat = 18
    static let panelVerticalPadding: CGFloat = 10
    static let panelCornerRadius: CGFloat = 22
    static let panelMinWidth: CGFloat = 280
    static let screenHorizontalMargin: CGFloat = 20
    static let fullWidthHorizontalMargin: CGFloat = 12
    static let scrollHintWidth: CGFloat = 2
    static let scrollHintVerticalInset: CGFloat = 10
    static let scrollHintTrailingInset: CGFloat = 6
    static let headerHeight: CGFloat = 32
    static let dividerHeight: CGFloat = 9
    static let triggerGap: CGFloat = 8
    static let popoverEdgeMargin: CGFloat = 12

    static var panelMaxWidth: CGFloat {
        min(UIScreen.main.bounds.width * 0.78, UIScreen.main.bounds.width - screenHorizontalMargin * 2)
    }

    static var scrollHintColor: Color { Color.white.opacity(0.28) }

    static var screenBounds: CGRect { UIScreen.main.bounds }

    static var currentSafeAreaInsets: UIEdgeInsets {
        guard
            let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
            let window = scene.windows.first(where: { $0.isKeyWindow && !$0.isHidden })
                ?? scene.windows.first(where: { !$0.isHidden })
        else { return .zero }
        return window.safeAreaInsets
    }

    static func anchoredPanelLayout(
        triggerFrame: CGRect,
        contentHeight: CGFloat,
        titles: [String],
        hasIcons: Bool = false,
        prefersFullWidth: Bool = false,
        screenBounds: CGRect = DSDropdownConfiguration.screenBounds,
        safeInsets: UIEdgeInsets = currentSafeAreaInsets
    ) -> (width: CGFloat, height: CGFloat, origin: CGPoint) {
        let width: CGFloat
        if prefersFullWidth {
            width = max(
                panelMinWidth,
                screenBounds.width - safeInsets.left - safeInsets.right - fullWidthHorizontalMargin * 2
            )
        } else {
            width = estimatedPanelWidth(for: titles, hasIcons: hasIcons)
        }
        let spaceBelow = screenBounds.maxY - safeInsets.bottom - triggerFrame.maxY - triggerGap - popoverEdgeMargin
        let spaceAbove = triggerFrame.minY - safeInsets.top - triggerGap - popoverEdgeMargin
        let opensDown = spaceBelow >= spaceAbove

        let available = max(0, opensDown ? spaceBelow : spaceAbove)
        let padded = contentHeight + panelVerticalPadding * 2
        let height = min(padded, min(maxVisibleHeight, available))

        let margin = prefersFullWidth ? fullWidthHorizontalMargin : screenHorizontalMargin / 2
        let minX = safeInsets.left + margin
        let maxX = screenBounds.width - safeInsets.right - width - margin
        var x = prefersFullWidth ? minX : (triggerFrame.midX - width / 2)
        x = min(max(x, minX), max(minX, maxX))

        var y: CGFloat
        if opensDown {
            y = triggerFrame.maxY + triggerGap
            let maxY = screenBounds.height - safeInsets.bottom - height - popoverEdgeMargin
            y = min(y, maxY)
        } else {
            y = triggerFrame.minY - triggerGap - height
            y = max(y, safeInsets.top + popoverEdgeMargin)
        }

        return (width, height, CGPoint(x: x, y: y))
    }

    static func estimatedPanelWidth(for titles: [String], hasIcons: Bool = false) -> CGFloat {
        guard !titles.isEmpty else { return panelMinWidth }
        let font = UIFont.systemFont(ofSize: 16, weight: .regular)
        let maxText = titles
            .map { ($0 as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
        let iconColumn: CGFloat = hasIcons ? 34 : 0
        let checkColumn: CGFloat = 28
        let horizontalPad = rowHorizontalPadding * 2
        let raw = ceil(maxText + iconColumn + checkColumn + horizontalPad + 12)
        let horizontalBudget = UIScreen.main.bounds.width - currentSafeAreaInsets.left - currentSafeAreaInsets.right - screenHorizontalMargin
        return min(max(raw, panelMinWidth), min(panelMaxWidth, horizontalBudget))
    }

    static func estimatedContentHeight(from items: [DSDropdownActionItem]) -> CGFloat {
        estimatedContentHeight(
            actionCount: items.filter { $0.kind == .action }.count,
            headerCount: items.filter { $0.kind == .header }.count,
            dividerCount: items.filter { $0.kind == .divider }.count
        )
    }

    static func estimatedContentHeight(optionCount: Int) -> CGFloat {
        estimatedContentHeight(actionCount: optionCount, headerCount: 0, dividerCount: 0)
    }

    static func estimatedContentHeight(actionCount: Int, headerCount: Int, dividerCount: Int) -> CGFloat {
        CGFloat(actionCount) * rowHeight
            + CGFloat(headerCount) * headerHeight
            + CGFloat(dividerCount) * dividerHeight
    }
}

// MARK: - Models

struct DSDropdownActionItem: Identifiable, Hashable {
    enum Kind: Hashable {
        case action
        case header
        case divider
    }

    let id: String
    let title: String
    var subtitle: String? = nil
    var systemImage: String?
    var kind: Kind = .action
    var isDestructive: Bool = false
    var isDisabled: Bool = false
    var isSelected: Bool = false

    static func header(_ title: String) -> DSDropdownActionItem {
        DSDropdownActionItem(id: "header-\(title)", title: title, kind: .header)
    }

    static func divider(_ id: String = UUID().uuidString) -> DSDropdownActionItem {
        DSDropdownActionItem(id: "divider-\(id)", title: "", kind: .divider)
    }

    static func action(
        _ id: String,
        _ title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        isDestructive: Bool = false,
        isDisabled: Bool = false,
        isSelected: Bool = false
    ) -> DSDropdownActionItem {
        DSDropdownActionItem(
            id: id,
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            kind: .action,
            isDestructive: isDestructive,
            isDisabled: isDisabled,
            isSelected: isSelected
        )
    }
}

// MARK: - Trigger frame (UIKit screen coordinates)

private final class DSDropdownTriggerFrameProxy {
    weak var anchorView: UIView?

    func captureFrame() -> CGRect {
        guard let anchorView else { return .zero }
        guard anchorView.window != nil else { return .zero }
        return anchorView.convert(anchorView.bounds, to: nil)
    }
}

private struct DSDropdownTriggerFrameReader: UIViewRepresentable {
    let proxy: DSDropdownTriggerFrameProxy
    @Binding var frame: CGRect

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        proxy.anchorView = uiView
        context.coordinator.report(from: uiView)
    }

    final class Coordinator {
        var parent: DSDropdownTriggerFrameReader

        init(parent: DSDropdownTriggerFrameReader) {
            self.parent = parent
        }

        func report(from view: UIView) {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let next = self.parent.proxy.captureFrame()
                guard next != .zero else { return }
                self.parent.frame = next
            }
        }
    }
}

// MARK: - Overlay window (above sheets / preview)

private final class DSDropdownOverlayWindowController {
    static let shared = DSDropdownOverlayWindowController()
    private var overlayWindow: UIWindow?

    func present<Content: View>(
        panelFrame: CGRect,
        onDismiss: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        dismiss()

        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }

        let shell = DSDropdownAnchoredShell(panelFrame: panelFrame, onDismiss: onDismiss, content: content)
        let host = UIHostingController(rootView: AnyView(shell))
        host.view.backgroundColor = .clear
        host.view.insetsLayoutMarginsFromSafeArea = false

        let window = UIWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        window.windowLevel = .alert + 2
        window.backgroundColor = .clear
        window.rootViewController = host
        window.isHidden = false
        overlayWindow = window
    }

    func dismiss() {
        overlayWindow?.isHidden = true
        overlayWindow?.rootViewController = nil
        overlayWindow = nil
    }
}

private struct DSDropdownAnchoredShell<Content: View>: View {
    let panelFrame: CGRect
    let onDismiss: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var appeared = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.38)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            content()
                .frame(width: panelFrame.width, height: panelFrame.height, alignment: .topLeading)
                .offset(x: panelFrame.minX, y: panelFrame.minY)
                .scaleEffect(appeared ? 1 : 0.94, anchor: .top)
                .opacity(appeared ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                appeared = true
            }
        }
    }
}

// MARK: - Panel chrome (liquid glass)

struct DSDropdownLiquidGlassBackground: View {
    var cornerRadius: CGFloat = DSDropdownConfiguration.panelCornerRadius

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.regularMaterial)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.black.opacity(0.58))
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(AppTheme.glassTint.opacity(0.9))
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.2),
                            Color.white.opacity(0.04),
                            Color.clear,
                            Color.white.opacity(0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.34),
                            AppTheme.goldBorderGlow,
                            Color.white.opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.55), radius: 28, x: 0, y: 14)
    }
}

struct DSDropdownPanelContainer<Content: View>: View {
    var panelWidth: CGFloat
    var panelHeight: CGFloat
    @ViewBuilder var content: () -> Content

    @State private var isPanelPressed = false

    var body: some View {
        content()
            .frame(
                width: panelWidth,
                height: max(0, panelHeight - DSDropdownConfiguration.panelVerticalPadding * 2),
                alignment: .topLeading
            )
            .padding(.vertical, DSDropdownConfiguration.panelVerticalPadding)
            .foregroundStyle(AppTheme.brandPanelBody)
            .tint(DS.ColorToken.accent)
            .background { DSDropdownLiquidGlassBackground() }
            .clipShape(RoundedRectangle(cornerRadius: DSDropdownConfiguration.panelCornerRadius, style: .continuous))
            .scaleEffect(isPanelPressed ? 1.014 : 1)
            .shadow(
                color: isPanelPressed ? AppTheme.goldBorderGlow.opacity(0.35) : .clear,
                radius: isPanelPressed ? 18 : 0,
                x: 0,
                y: isPanelPressed ? -4 : 0
            )
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isPanelPressed)
            .onPreferenceChange(DSDropdownPanelPressKey.self) { isPanelPressed = $0 }
    }
}

// MARK: - Scroll / fit panel

private struct DSDropdownContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct DSDropdownScrollHintLine: View {
    var body: some View {
        Rectangle()
            .fill(DSDropdownConfiguration.scrollHintColor)
            .frame(width: DSDropdownConfiguration.scrollHintWidth)
            .padding(.vertical, DSDropdownConfiguration.scrollHintVerticalInset)
            .padding(.trailing, DSDropdownConfiguration.scrollHintTrailingInset)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct DSDropdownScrollPanel<Content: View>: View {
    let maxContentHeight: CGFloat
    let estimatedContentHeight: CGFloat
    let selectedScrollID: AnyHashable?
    let topScrollID: AnyHashable?
    @ViewBuilder var content: () -> Content

    @State private var measuredHeight: CGFloat = 0

    private var contentHeight: CGFloat {
        max(measuredHeight, estimatedContentHeight)
    }

    private var needsScroll: Bool {
        contentHeight > maxContentHeight + 1
    }

    private var displayHeight: CGFloat {
        needsScroll ? maxContentHeight : contentHeight
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Group {
                if needsScroll {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            contentStack
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .onAppear { scrollOnOpen(using: proxy) }
                    }
                } else {
                    contentStack
                }
            }
            .frame(height: displayHeight, alignment: .top)

            if needsScroll {
                DSDropdownScrollHintLine()
            }
        }
        .background {
            contentStack
                .fixedSize(horizontal: false, vertical: true)
                .hidden()
                .background {
                    GeometryReader { geo in
                        Color.clear.preference(key: DSDropdownContentHeightKey.self, value: geo.size.height)
                    }
                }
        }
        .onPreferenceChange(DSDropdownContentHeightKey.self) { measuredHeight = $0 }
    }

    private var contentStack: some View {
        content()
    }

    private func scrollOnOpen(using proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            if let selectedScrollID {
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(selectedScrollID, anchor: .center)
                }
            } else if let topScrollID {
                proxy.scrollTo(topScrollID, anchor: .top)
            }
        }
    }
}

// MARK: - Liquid glass touch feedback

private struct DSDropdownPanelPressKey: PreferenceKey {
    static var defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

/// Brand-aligned melt highlight shown while a row is pressed.
private struct DSDropdownRowPressGlow: View {
    var isPressed: Bool

    var body: some View {
        GeometryReader { geo in
            if isPressed {
                RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [
                                AppTheme.mint.opacity(0.42),
                                AppTheme.mint.opacity(0.16),
                                Color.white.opacity(0.05),
                                .clear
                            ],
                            center: .center,
                            startRadius: 4,
                            endRadius: max(geo.size.width, geo.size.height) * 0.85
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                            .stroke(AppTheme.mint.opacity(0.28), lineWidth: 0.5)
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .allowsHitTesting(false)
        .animation(DS.Motion.pressSpringSoft, value: isPressed)
    }
}

private struct DSDropdownRowButtonStyle: ButtonStyle {
    var isDisabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                DSDropdownRowPressGlow(isPressed: configuration.isPressed && !isDisabled)
            }
            .background {
                Color.clear
                    .preference(key: DSDropdownPanelPressKey.self, value: configuration.isPressed && !isDisabled)
            }
            .scaleEffect(configuration.isPressed && !isDisabled ? DS.Motion.pressScale : 1)
            .brightness(configuration.isPressed && !isDisabled ? 0.03 : 0)
            .animation(DS.Motion.pressSpring, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed, !isDisabled {
                    InteractionHaptics.tapPreferringSettings()
                }
            }
    }
}

private struct DSDropdownTriggerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if configuration.isPressed {
                    RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                        .fill(AppTheme.mint.opacity(0.14))
                }
            }
            .scaleEffect(configuration.isPressed ? DS.Motion.pressScale : 1)
            .animation(DS.Motion.pressSpring, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { InteractionHaptics.tapPreferringSettings() }
            }
    }
}

// MARK: - Trigger + rows

struct DSDropdownTriggerLabel: View {
    let valueTitle: String
    var showsChevron: Bool = true

    var body: some View {
        HStack(spacing: 6) {
            Text(valueTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.ColorToken.label)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            if showsChevron {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DS.ColorToken.secondaryLabel)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.ColorToken.backgroundTertiary, in: RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                .stroke(DS.ColorToken.separator, lineWidth: 1)
        )
    }
}

struct DSDropdownRowButton: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String?
    var isSelected: Bool = false
    var isDestructive: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isDestructive ? DS.ColorToken.error : Color.white.opacity(0.95))
                        .frame(width: 20, alignment: .center)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title)
                        .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(
                            isDestructive
                                ? DS.ColorToken.error
                                : (isSelected ? AppTheme.brandPanelTitle : Color.white.opacity(0.94))
                        )
                        .multilineTextAlignment(.leading)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.52))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppTheme.brandPanelTitle)
                        .frame(width: 18, alignment: .center)
                }
            }
            .padding(.horizontal, DSDropdownConfiguration.rowHorizontalPadding)
            .frame(height: DSDropdownConfiguration.rowHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(DSDropdownRowButtonStyle(isDisabled: isDisabled))
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.goldBorderGlow.opacity(0.14))
                    .padding(.horizontal, 8)
            }
        }
    }
}

// MARK: - Shared presentation

private enum DSDropdownPresenter {
    static func open(
        panelFrame: CGRect,
        panelWidth: CGFloat,
        panelHeight: CGFloat,
        maxContentHeight: CGFloat,
        estimatedContentHeight: CGFloat,
        selectedScrollID: AnyHashable?,
        topScrollID: AnyHashable?,
        onDismiss: @escaping () -> Void,
        @ViewBuilder rows: @escaping () -> some View
    ) {
        DSDropdownOverlayWindowController.shared.present(panelFrame: panelFrame, onDismiss: onDismiss) {
            DSDropdownPanelContainer(panelWidth: panelWidth, panelHeight: panelHeight) {
                DSDropdownScrollPanel(
                    maxContentHeight: maxContentHeight,
                    estimatedContentHeight: estimatedContentHeight,
                    selectedScrollID: selectedScrollID,
                    topScrollID: topScrollID,
                    content: rows
                )
            }
        }
    }

    static func close() {
        DSDropdownOverlayWindowController.shared.dismiss()
    }
}

// MARK: - Menu layout helper

private struct DSDropdownMenuLayout {
    let panelWidth: CGFloat
    let panelHeight: CGFloat
    let panelOrigin: CGPoint
    let maxContentHeight: CGFloat

    var panelFrame: CGRect {
        CGRect(x: panelOrigin.x, y: panelOrigin.y, width: panelWidth, height: panelHeight)
    }
}

private enum DSDropdownMenuLayoutBuilder {
    static func layout(
        triggerFrame: CGRect,
        contentHeight: CGFloat,
        titles: [String],
        hasIcons: Bool,
        maxHeight: CGFloat?,
        prefersFullWidth: Bool = false
    ) -> DSDropdownMenuLayout {
        let anchored = DSDropdownConfiguration.anchoredPanelLayout(
            triggerFrame: triggerFrame,
            contentHeight: contentHeight,
            titles: titles,
            hasIcons: hasIcons,
            prefersFullWidth: prefersFullWidth
        )
        var maxContentHeight = anchored.height - DSDropdownConfiguration.panelVerticalPadding * 2
        if let maxHeight {
            maxContentHeight = min(maxContentHeight, maxHeight - DSDropdownConfiguration.panelVerticalPadding * 2)
        }
        return DSDropdownMenuLayout(
            panelWidth: anchored.width,
            panelHeight: anchored.height,
            panelOrigin: anchored.origin,
            maxContentHeight: max(0, maxContentHeight)
        )
    }
}

// MARK: - Action menu

struct DSDropdownActionMenu<Label: View>: View {
    @ViewBuilder let label: () -> Label
    let items: [DSDropdownActionItem]
    var maxHeight: CGFloat?
    var isEnabled: Bool = true
    var prefersFullWidth: Bool = false
    let onSelect: (DSDropdownActionItem) -> Void

    @State private var triggerFrame: CGRect = .zero
    @StateObject private var frameProxy = ObservedFrameProxy()

    private var selectedScrollID: AnyHashable? {
        items.first(where: { $0.kind == .action && $0.isSelected })?.id
    }

    private var topScrollID: AnyHashable? {
        items.first(where: { $0.kind == .action })?.id
    }

    private var estimatedContentHeight: CGFloat {
        DSDropdownConfiguration.estimatedContentHeight(from: items)
    }

    var body: some View {
        Button(action: openMenu) {
            label()
                .background {
                    DSDropdownTriggerFrameReader(proxy: frameProxy.proxy, frame: $triggerFrame)
                }
        }
        .buttonStyle(DSDropdownTriggerButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }

    private func openMenu() {
        guard isEnabled else { return }

        let captured = frameProxy.proxy.captureFrame()
        let frame = captured != .zero ? captured : triggerFrame
        let layout = buildLayout(triggerFrame: frame)

        DSDropdownPresenter.open(
            panelFrame: layout.panelFrame,
            panelWidth: layout.panelWidth,
            panelHeight: layout.panelHeight,
            maxContentHeight: layout.maxContentHeight,
            estimatedContentHeight: estimatedContentHeight,
            selectedScrollID: selectedScrollID,
            topScrollID: topScrollID,
            onDismiss: { DSDropdownPresenter.close() }
        ) {
            VStack(spacing: 0) {
                ForEach(items) { item in
                    switch item.kind {
                    case .divider:
                        Divider().overlay(Color.white.opacity(0.14)).padding(.vertical, 2)
                    case .header:
                        Text(item.title)
                            .font(DS.TypeScale.caption.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.62))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, DSDropdownConfiguration.rowHorizontalPadding)
                            .frame(height: DSDropdownConfiguration.headerHeight, alignment: .leading)
                    case .action:
                        DSDropdownRowButton(
                            title: item.title,
                            subtitle: item.subtitle,
                            systemImage: item.systemImage,
                            isSelected: item.isSelected,
                            isDestructive: item.isDestructive,
                            isDisabled: item.isDisabled
                        ) {
                            guard !item.isDisabled else { return }
                            DSDropdownPresenter.close()
                            onSelect(item)
                        }
                        .id(item.id)
                    }
                }
            }
        }
    }

    private func buildLayout(triggerFrame: CGRect) -> DSDropdownMenuLayout {
        let titles = items.filter { $0.kind == .action }.map { item in
            if let subtitle = item.subtitle, !subtitle.isEmpty {
                return "\(item.title)  \(subtitle)"
            }
            return item.title
        }
        let hasIcons = items.contains { $0.kind == .action && $0.systemImage != nil }
        return DSDropdownMenuLayoutBuilder.layout(
            triggerFrame: triggerFrame,
            contentHeight: estimatedContentHeight,
            titles: titles,
            hasIcons: hasIcons,
            maxHeight: maxHeight,
            prefersFullWidth: prefersFullWidth
        )
    }
}

// MARK: - Selection menu

struct DSDropdownSelectionMenu<ID: Hashable>: View {
    var title: String?
    let valueTitle: String
    @Binding var selection: ID
    let options: [(id: ID, title: String)]
    var isEnabled: Bool = true
    var maxHeight: CGFloat?

    @State private var triggerFrame: CGRect = .zero
    @StateObject private var frameProxy = ObservedFrameProxy()

    private var estimatedContentHeight: CGFloat {
        DSDropdownConfiguration.estimatedContentHeight(optionCount: options.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title {
                Text(title)
                    .font(DS.TypeScale.caption.weight(.semibold))
                    .foregroundStyle(DS.ColorToken.secondaryLabel)
            }

            Button(action: openMenu) {
                DSDropdownTriggerLabel(valueTitle: valueTitle)
                    .background {
                        DSDropdownTriggerFrameReader(proxy: frameProxy.proxy, frame: $triggerFrame)
                    }
            }
            .buttonStyle(DSDropdownTriggerButtonStyle())
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.45)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func openMenu() {
        guard isEnabled else { return }

        let captured = frameProxy.proxy.captureFrame()
        let frame = captured != .zero ? captured : triggerFrame
        let layout = DSDropdownMenuLayoutBuilder.layout(
            triggerFrame: frame,
            contentHeight: estimatedContentHeight,
            titles: options.map(\.title),
            hasIcons: false,
            maxHeight: maxHeight
        )

        DSDropdownPresenter.open(
            panelFrame: layout.panelFrame,
            panelWidth: layout.panelWidth,
            panelHeight: layout.panelHeight,
            maxContentHeight: layout.maxContentHeight,
            estimatedContentHeight: estimatedContentHeight,
            selectedScrollID: AnyHashable(selection),
            topScrollID: options.first.map { AnyHashable($0.id) },
            onDismiss: { DSDropdownPresenter.close() }
        ) {
            VStack(spacing: 0) {
                ForEach(options, id: \.id) { option in
                    DSDropdownRowButton(
                        title: option.title,
                        isSelected: selection == option.id
                    ) {
                        selection = option.id
                        DSDropdownPresenter.close()
                    }
                    .id(option.id)
                }
            }
        }
    }
}

/// Holds a stable frame proxy for `@StateObject` lifetime.
private final class ObservedFrameProxy: ObservableObject {
    let proxy = DSDropdownTriggerFrameProxy()
}
