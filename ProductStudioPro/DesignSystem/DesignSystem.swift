import SwiftUI
import UIKit

// MARK: - Global design tokens (single source of truth)

enum DS {
    enum ColorToken {
        /// Brand page chrome — light and dark each have their own surface stack.
        static let background = adaptive(light: BrandPalette.lightBackground, dark: BrandPalette.darkBackground)
        static let backgroundSecondary = adaptive(light: BrandPalette.lightCard, dark: BrandPalette.darkSurface)
        static let backgroundTertiary = adaptive(light: BrandPalette.lightSurface, dark: BrandPalette.darkCard)
        static let groupedBackground = adaptive(light: BrandPalette.lightBackground, dark: BrandPalette.darkBackground)
        static let groupedSecondary = adaptive(light: BrandPalette.lightCard, dark: BrandPalette.darkSurface)

        static let label = Color(.label)
        static let secondaryLabel = Color(.secondaryLabel)
        static let tertiaryLabel = Color(.tertiaryLabel)
        static let placeholderText = Color(.placeholderText)

        static let separator = adaptive(light: BrandPalette.lightBorder, dark: BrandPalette.darkBorder)
        static let opaqueSeparator = adaptive(light: BrandPalette.lightBorder, dark: BrandPalette.darkBorder)

        /// Light: charcoal slate. Dark: seafoam mint accent.
        static var accent: Color { AppTheme.brandAccent }
        static var accentFill: Color { AppTheme.brandAccent }
        static var onAccent: Color {
            Color(UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(hex: BrandPalette.charcoal)
                    : .white
            })
        }

        static var primaryButtonFill: Color {
            Color(UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(hex: BrandPalette.mint)
                    : UIColor(hex: BrandPalette.charcoal)
            })
        }

        private static func adaptive(light: String, dark: String) -> Color {
            Color(UIColor { traits in
                UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
            })
        }

        /// Brand-aligned semantic colors (shared with `AppTheme`).
        static let success = Color(hex: "#22C55E")
        static let warning = Color(hex: "#FBBF24")
        static let error = Color(hex: "#EF4444")

        static let scrim = Color(.label).opacity(0.45)
        static let elevatedShadow = Color(.label).opacity(0.12)
    }

    enum Space {
        static let screenHorizontal: CGFloat = 18
        static let screenVertical: CGFloat = 16
        static let section: CGFloat = 14
        static let stack: CGFloat = 10
        static let tight: CGFloat = 6
        static let cardPadding: CGFloat = 12
        static let listRowInsetH: CGFloat = 2
        static let listRowSpacing: CGFloat = 8
    }

    enum Radius {
        static let card: CGFloat = 18
        static let control: CGFloat = 14
        static let chip: CGFloat = 12
        static let queueRow: CGFloat = 16
        static let thumbnail: CGFloat = 8
        /// Compact primary / danger chips.
        static let compactControl: CGFloat = 12
    }

    enum TypeScale {
        static let screenTitle = Font.system(size: 28, weight: .bold)
        static let pageTitle = Font.system(size: 22, weight: .semibold)
        static let sectionTitle = Font.system(size: 17, weight: .semibold)
        static let rowTitle = Font.system(size: 15, weight: .semibold)
        static let body = Font.system(size: 15, weight: .regular)
        static let bodyEmphasis = Font.system(size: 15, weight: .medium)
        static let caption = Font.system(size: 12, weight: .medium)
        static let micro = Font.system(size: 11, weight: .semibold)
        static let nano = Font.system(size: 10, weight: .heavy)
        static let dockSection = Font.system(size: 13, weight: .semibold)
        /// Dashboard / queue metric numerals (Queued, Next).
        static let metricValue = Font.system(size: 28, weight: .bold)
        static let metricLabel = Font.system(size: 12, weight: .medium)
    }

    /// Global press / spring motion — use everywhere tappable controls animate.
    enum Motion {
        static let pressScale: CGFloat = 0.92
        static let pressScaleCompact: CGFloat = 0.88
        static let pressScaleIcon: CGFloat = 0.84
        /// How long to keep the press visual before running navigation / sheet actions.
        static let tapActionDelayNanoseconds: UInt64 = 110_000_000
        static let pressSpring = Animation.spring(response: 0.22, dampingFraction: 0.62)
        static let pressSpringSoft = Animation.spring(response: 0.20, dampingFraction: 0.78)
        static let disabledOpacity: Double = 0.38
        static let disabledSaturation: Double = 0.35
        static let pressedBrightness: Double = -0.08
        static let pressedOpacity: Double = 0.88
    }

    enum Shadow {
        static let card = (color: ColorToken.elevatedShadow, radius: CGFloat(8), y: CGFloat(3))
    }
}

// MARK: - Catalog processing baseline (Standard chip / reset target)

enum CatalogProcessingBaseline {
    static let mode: PhotoEnhancementMode = .standardClean
    static let strength: StudioAIStrength = .natural
}

// MARK: - Screen scaffold

enum AppScreenLayout {
    /// Standard vertical scroll (Settings, Home).
    case scroll
    /// Fixed header + flexible body (Queue list).
    case listBody
}

struct AppScreenScaffold<Content: View, Footer: View, HeaderAccessory: View>: View {
    var title: String
    var subtitle: String?
    var showsHome: Bool = true
    var popToRoot: (() -> Void)?
    /// Non-root routes pass these to render the standardized leading back + home header controls.
    var onBack: (() -> Void)?
    var onHome: (() -> Void)?
    var layout: AppScreenLayout = .scroll
    var usesLargeTitle: Bool = false
    var scrollDismissesKeyboardInteractively: Bool = false
    @ViewBuilder var headerAccessory: () -> HeaderAccessory
    @ViewBuilder var footer: () -> Footer
    @ViewBuilder var content: () -> Content

    init(
        title: String,
        subtitle: String? = nil,
        showsHome: Bool = true,
        popToRoot: (() -> Void)? = nil,
        onBack: (() -> Void)? = nil,
        onHome: (() -> Void)? = nil,
        layout: AppScreenLayout = .scroll,
        usesLargeTitle: Bool = false,
        scrollDismissesKeyboardInteractively: Bool = false,
        @ViewBuilder headerAccessory: @escaping () -> HeaderAccessory = { EmptyView() },
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder footer: @escaping () -> Footer = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.showsHome = showsHome
        self.popToRoot = popToRoot
        self.onBack = onBack
        self.onHome = onHome
        self.layout = layout
        self.usesLargeTitle = usesLargeTitle
        self.scrollDismissesKeyboardInteractively = scrollDismissesKeyboardInteractively
        self.headerAccessory = headerAccessory
        self.content = content
        self.footer = footer
    }

    var body: some View {
        ZStack {
            PremiumBackgroundView()
            VStack(spacing: 0) {
                screenHeader
                switch layout {
                case .scroll:
                    ScrollView {
                        VStack(alignment: .leading, spacing: DS.Space.section) {
                            content()
                        }
                        .padding(.horizontal, DS.Space.screenHorizontal)
                        .padding(.bottom, DS.Space.screenVertical)
                    }
                    .scrollDismissesKeyboard(scrollDismissesKeyboardInteractively ? .interactively : .automatic)
                case .listBody:
                    VStack(alignment: .leading, spacing: DS.Space.listRowSpacing) {
                        content()
                    }
                    .padding(.horizontal, DS.Space.screenHorizontal)
                    .padding(.bottom, DS.Space.tight)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                footer()
            }
        }
        .modifier(HomeToolbarModifier(showsHome: showsHome, popToRoot: popToRoot))
    }

    private var screenHeader: some View {
        VStack(alignment: .leading, spacing: DS.Space.tight) {
            if onBack != nil || onHome != nil {
                navigationControls
            }
            VStack(alignment: .leading, spacing: DS.Space.tight) {
                Text(title)
                    .font(usesLargeTitle ? DS.TypeScale.screenTitle : DS.TypeScale.pageTitle)
                    .foregroundStyle(DS.ColorToken.label)
                if let subtitle {
                    DSAccentSubtitleChip(text: subtitle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Space.screenHorizontal)
        .padding(.top, DS.Space.screenVertical)
        .padding(.bottom, DS.Space.tight)
    }

    /// Leading back/home controls with optional trailing header accessory on the same row.
    private var navigationControls: some View {
        HStack(spacing: DS.Space.tight) {
            if let onBack {
                DSFloatingChromeButton(systemName: "chevron.left", accessibilityLabel: "Back", action: onBack)
            }
            if let onHome {
                DSFloatingChromeButton(systemName: "house", accessibilityLabel: "Home", action: onHome)
            }
            Spacer(minLength: 0)
            headerAccessory()
        }
    }
}

/// Bottom sheet / pinned inspector (Format Background).
struct DSSheetPanelScaffold<Content: View>: View {
    let title: String
    var doneTitle: String = "Done"
    var onDone: () -> Void
    var maxHeightRatio: CGFloat = 0.52
    var maxHeightCap: CGFloat = 440
    /// When false, content is laid out without an inner scroll view (compact inspectors).
    var isScrollEnabled: Bool = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        let scrollHeightCap = min(UIScreen.main.bounds.height * maxHeightRatio, maxHeightCap)

        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(DS.TypeScale.sectionTitle)
                    .foregroundStyle(DS.ColorToken.label)
                Spacer()
                Button(doneTitle, action: onDone)
                    .font(DS.TypeScale.bodyEmphasis)
                    .foregroundStyle(DS.ColorToken.accent)
            }
            .padding(.horizontal, DS.Space.screenHorizontal - 4)
            .padding(.vertical, DS.Space.stack)

            Divider().overlay(DS.ColorToken.separator)

            if isScrollEnabled {
                ScrollView {
                    panelContent
                }
                .frame(maxHeight: scrollHeightCap)
            } else {
                panelContent
            }
        }
        .fixedSize(horizontal: false, vertical: !isScrollEnabled)
        .frame(maxHeight: isScrollEnabled ? scrollHeightCap : nil)
        .background(DS.ColorToken.backgroundSecondary)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(DS.ColorToken.separator), alignment: .top)
        .safeAreaPadding(.bottom, DS.Space.stack)
    }

    private var panelContent: some View {
        content()
            .padding(.horizontal, DS.Space.screenHorizontal - 6)
            .padding(.top, DS.Space.stack)
            .padding(.bottom, isScrollEnabled ? DS.Space.screenVertical : DS.Space.stack)
    }
}

// MARK: - UIKit bridge (operational sheets / markup)

/// Semantic UIKit tokens mirroring `DS.ColorToken`, `DS.Space`, and `DS.TypeScale`.
enum DSUIKit {
    static let panelBackground = UIColor.secondarySystemBackground
    static let chipBackground = UIColor.tertiarySystemBackground
    static let separator = UIColor.separator
    static let label = UIColor.label
    static let secondaryLabel = UIColor.secondaryLabel

    static let sectionTitleFont = UIFont.systemFont(ofSize: 17, weight: .semibold)
    static let bodyEmphasisFont = UIFont.systemFont(ofSize: 15, weight: .medium)
    static let dockSectionFont = UIFont.systemFont(ofSize: 13, weight: .semibold)
    static let captionFont = UIFont.systemFont(ofSize: 12, weight: .medium)
    static let microFont = UIFont.systemFont(ofSize: 11, weight: .semibold)

    static let headerHorizontalPadding = DS.Space.screenHorizontal - 4
    static let headerVerticalPadding = DS.Space.stack
    static let contentHorizontalPadding = DS.Space.screenHorizontal - 6

    static func pageBackground(_ traits: UITraitCollection) -> UIColor {
        traits.userInterfaceStyle == .dark
            ? UIColor(hex: BrandPalette.darkBackground)
            : UIColor(hex: BrandPalette.lightBackground)
    }

    static func accent(_ traits: UITraitCollection) -> UIColor {
        traits.userInterfaceStyle == .dark
            ? UIColor(hex: BrandPalette.mint)
            : UIColor(hex: BrandPalette.charcoal)
    }

    static func chipSelectedBackground(_ traits: UITraitCollection) -> UIColor {
        UIColor(hex: BrandPalette.mint).withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.38 : 0.45)
    }

    static func chipSelectedBorder(_ traits: UITraitCollection) -> UIColor {
        accent(traits)
    }

    /// Same spring as preview slide-up sheets (`response` 0.36, `damping` 0.86).
    static func animateOperationalSheet(
        animations: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil
    ) {
        UIView.animate(
            withDuration: 0.36,
            delay: 0,
            usingSpringWithDamping: 0.86,
            initialSpringVelocity: 0,
            animations: animations,
            completion: completion
        )
    }

    /// Installs global press scale + light haptic on any UIControl (buttons, chips).
    static func installPressFeedback(
        on control: UIControl,
        scale: CGFloat = DS.Motion.pressScale,
        vibrateEnabled: @escaping () -> Bool = { true }
    ) {
        if objc_getAssociatedObject(control, &DSUIKitPressFeedbackKeys.handler) != nil { return }

        let handler = DSUIKitPressFeedbackHandler(control: control, scale: scale, vibrateEnabled: vibrateEnabled)
        objc_setAssociatedObject(control, &DSUIKitPressFeedbackKeys.handler, handler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        control.addTarget(handler, action: #selector(DSUIKitPressFeedbackHandler.touchDown), for: .touchDown)
        control.addTarget(handler, action: #selector(DSUIKitPressFeedbackHandler.touchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
    }

    static func animatePressDown(_ view: UIView, scale: CGFloat = DS.Motion.pressScale) {
        UIView.animate(
            withDuration: 0.18,
            delay: 0,
            usingSpringWithDamping: 0.55,
            initialSpringVelocity: 0.8,
            options: [.allowUserInteraction, .beginFromCurrentState],
            animations: {
                view.transform = CGAffineTransform(scaleX: scale, y: scale)
            }
        )
    }

    static func animatePressUp(_ view: UIView) {
        UIView.animate(
            withDuration: 0.22,
            delay: 0,
            usingSpringWithDamping: 0.62,
            initialSpringVelocity: 0.4,
            options: [.allowUserInteraction, .beginFromCurrentState],
            animations: {
                view.transform = .identity
            }
        )
    }
}

private enum DSUIKitPressFeedbackKeys {
    static var handler: UInt8 = 0
}

private final class DSUIKitPressFeedbackHandler: NSObject {
    weak var control: UIControl?
    let scale: CGFloat
    let vibrateEnabled: () -> Bool

    init(control: UIControl, scale: CGFloat, vibrateEnabled: @escaping () -> Bool) {
        self.control = control
        self.scale = scale
        self.vibrateEnabled = vibrateEnabled
    }

    @objc func touchDown() {
        guard let control, control.isEnabled else { return }
        InteractionHaptics.tap(vibrate: vibrateEnabled())
        DSUIKit.animatePressDown(control, scale: scale)
    }

    @objc func touchUp() {
        guard let control else { return }
        DSUIKit.animatePressUp(control)
    }
}

/// Full-width operational shelf surface — matches `DSSheetPanelScaffold` (secondary fill + top hairline).
final class DSOperationalSheetSurfaceView: UIView {
    private let topHairline = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = DSUIKit.panelBackground
        topHairline.backgroundColor = DSUIKit.separator
        topHairline.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topHairline)
        NSLayoutConstraint.activate([
            topHairline.topAnchor.constraint(equalTo: topAnchor),
            topHairline.leadingAnchor.constraint(equalTo: leadingAnchor),
            topHairline.trailingAnchor.constraint(equalTo: trailingAnchor),
            topHairline.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}

private struct HomeToolbarModifier: ViewModifier {
    var showsHome: Bool
    var popToRoot: (() -> Void)?

    func body(content: Content) -> some View {
        if showsHome, let popToRoot {
            content.homeShortcutToolbar(popToRoot: popToRoot)
        } else {
            content
        }
    }
}

// MARK: - Reusable components

struct DSCard<Content: View>: View {
    var padding: CGFloat = DS.Space.cardPadding
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.ColorToken.backgroundSecondary, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .stroke(DS.ColorToken.separator, lineWidth: 1)
            )
    }
}

struct DSPageSectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(DS.TypeScale.sectionTitle)
                .foregroundStyle(DS.ColorToken.label)
            if let subtitle {
                Text(subtitle)
                    .font(DS.TypeScale.caption)
                    .foregroundStyle(DS.ColorToken.secondaryLabel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Menu picker with unified dropdown scroll panel, scroll hint, and auto-scroll behavior.
struct DSFormMenuPicker<Selection: Hashable>: View {
    let title: String
    let valueTitle: String
    @Binding var selection: Selection
    let options: [(id: Selection, title: String)]
    var isEnabled: Bool = true

    var body: some View {
        DSDropdownSelectionMenu(
            title: title,
            valueTitle: valueTitle,
            selection: $selection,
            options: options,
            isEnabled: isEnabled
        )
    }
}

extension View {
    /// Adaptive label + accent caret for text fields on sheets and custom card backgrounds.
    func dsSemanticTextField() -> some View {
        font(DS.TypeScale.body)
            .tint(DS.ColorToken.accent)
    }
}

/// Side-by-side Solid / Gradient fill choice for Format Background.
struct DSFillKindChoice: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? DS.ColorToken.accent : DS.ColorToken.secondaryLabel)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.ColorToken.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .padding(.horizontal, 8)
            .background(
                isSelected ? DS.ColorToken.accent.opacity(0.14) : DS.ColorToken.backgroundTertiary,
                in: RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                    .stroke(isSelected ? DS.ColorToken.accent : DS.ColorToken.separator, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plainPressable)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct DSSegmentedChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DS.TypeScale.micro.weight(.heavy))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .foregroundStyle(isSelected ? DS.ColorToken.onAccent : DS.ColorToken.label)
                .background {
                    RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                        .fill(isSelected ? DS.ColorToken.primaryButtonFill : DS.ColorToken.backgroundTertiary)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                        .strokeBorder(
                            isSelected ? DS.ColorToken.accent : DS.ColorToken.separator,
                            lineWidth: isSelected ? 2.5 : 1
                        )
                }
                .shadow(
                    color: isSelected ? DS.ColorToken.accent.opacity(colorScheme == .dark ? 0.35 : 0.18) : .clear,
                    radius: isSelected ? 6 : 0,
                    y: 2
                )
        }
        .buttonStyle(.plainPressable)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct DSPrimaryButton: View {
    let title: String
    let systemImage: String?
    var isDisabled: Bool = false
    var isLoading: Bool = false
    let action: () -> Void

    init(
        _ title: String,
        systemImage: String? = nil,
        isDisabled: Bool = false,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isDisabled = isDisabled
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button {
            guard !isDisabled, !isLoading else { return }
            action()
        } label: {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(DS.ColorToken.onAccent)
                        .scaleEffect(0.85)
                }
                Group {
                    if let systemImage, !isLoading {
                        Label(title, systemImage: systemImage)
                    } else {
                        Text(title)
                    }
                }
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(isDisabled || isLoading)
        .opacity(isDisabled || isLoading ? DS.Motion.disabledOpacity : 1)
        .saturation(isDisabled || isLoading ? DS.Motion.disabledSaturation : 1)
    }
}

struct DSSecondaryButton: View {
    let title: String
    let systemImage: String?
    var isDisabled: Bool = false
    var isLoading: Bool = false
    let action: () -> Void

    init(
        _ title: String,
        systemImage: String? = nil,
        isDisabled: Bool = false,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isDisabled = isDisabled
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button {
            guard !isDisabled, !isLoading else { return }
            action()
        } label: {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.85)
                }
                Group {
                    if let systemImage, !isLoading {
                        Label(title, systemImage: systemImage)
                    } else {
                        Text(title)
                    }
                }
            }
        }
        .buttonStyle(SecondaryButtonStyle())
        .disabled(isDisabled || isLoading)
        .opacity(isDisabled || isLoading ? DS.Motion.disabledOpacity : 1)
        .saturation(isDisabled || isLoading ? DS.Motion.disabledSaturation : 1)
    }
}

struct DSStyleThumbnailPlaceholder: View {
    var size: CGSize

    var body: some View {
        Rectangle()
            .fill(DS.ColorToken.backgroundTertiary)
            .overlay {
                ProgressView()
                    .controlSize(.small)
                    .tint(DS.ColorToken.secondaryLabel)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.thumbnail, style: .continuous))
    }
}

// MARK: - Dashboard & queue patterns

struct DSAccentSubtitleChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(DS.TypeScale.caption.weight(.semibold))
            .foregroundStyle(DS.ColorToken.accent)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(DS.ColorToken.backgroundTertiary, in: Capsule())
            .overlay(Capsule().stroke(DS.ColorToken.separator, lineWidth: 1))
    }
}

struct DSMetricStatusCard: View {
    let title: String
    let value: String
    var showsChevron: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.stack) {
            VStack(alignment: .leading, spacing: DS.Space.tight) {
                Text(title)
                    .font(DS.TypeScale.metricLabel)
                    .foregroundStyle(DS.ColorToken.secondaryLabel)
                    .lineLimit(1)
                Text(value)
                    .font(DS.TypeScale.metricValue)
                    .foregroundStyle(DS.ColorToken.label)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .truncationMode(.tail)
                    .frame(minHeight: 28, alignment: .leading)
            }
            Spacer(minLength: 0)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(DS.TypeScale.caption.weight(.bold))
                    .foregroundStyle(DS.ColorToken.tertiaryLabel)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct DSStatusPill: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(DS.TypeScale.micro.weight(.bold))
                .foregroundStyle(DS.ColorToken.accent)
            Text(text)
                .font(DS.TypeScale.micro)
                .foregroundStyle(DS.ColorToken.secondaryLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.74)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(DS.ColorToken.backgroundTertiary, in: Capsule())
        .overlay(Capsule().stroke(DS.ColorToken.separator.opacity(0.85), lineWidth: 1))
    }
}

struct DSSectionCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        DSCard(padding: DS.Space.cardPadding + 4) {
            VStack(alignment: .leading, spacing: DS.Space.stack + 2) {
                HStack(spacing: DS.Space.stack) {
                    IconBadge(systemName: icon, dimension: 38, iconFontSize: 16)
                    Text(title)
                        .font(DS.TypeScale.sectionTitle)
                        .foregroundStyle(DS.ColorToken.label)
                }
                VStack(alignment: .leading, spacing: DS.Space.stack) {
                    content()
                }
            }
        }
        .shadow(color: DS.Shadow.card.color, radius: DS.Shadow.card.radius, x: 0, y: DS.Shadow.card.y)
    }
}

struct DSDivider: View {
    var body: some View {
        Divider().overlay(DS.ColorToken.separator)
    }
}

struct DSListRowCard<Content: View>: View {
    var isSelected: Bool = false
    var compact: Bool = false
    @ViewBuilder var content: () -> Content

    private var verticalPadding: CGFloat { compact ? 7 : DS.Space.cardPadding }
    private var horizontalPadding: CGFloat { compact ? 10 : DS.Space.cardPadding }
    private var cornerRadius: CGFloat { compact ? 12 : DS.Radius.queueRow }
    private var shadowRadius: CGFloat { compact ? 4 : DS.Shadow.card.radius }
    private var shadowY: CGFloat { compact ? 1 : DS.Shadow.card.y }

    var body: some View {
        content()
            .padding(.vertical, verticalPadding)
            .padding(.horizontal, horizontalPadding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isSelected ? DS.ColorToken.backgroundTertiary : DS.ColorToken.backgroundSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(isSelected ? DS.ColorToken.accent : DS.ColorToken.separator, lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: DS.Shadow.card.color, radius: shadowRadius, x: 0, y: shadowY)
    }
}

struct DSPrimaryActionStack<Content: View>: View {
    var spacing: CGFloat = DS.Space.stack
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: spacing) {
            content()
        }
    }
}

/// Settings-style helper copy inside cards.
struct DSHelperText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HelperInfoBox(text: text)
    }
}

typealias SettingsSectionCard = DSSectionCard

// MARK: - Capture flow

/// Mode selector chip (multi-angle progress).
struct DSCaptureModeChip: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        Text(title)
            .font(DS.TypeScale.micro)
            .foregroundStyle(isSelected ? DS.ColorToken.onAccent : DS.ColorToken.label)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(isSelected ? DS.ColorToken.primaryButtonFill : DS.ColorToken.backgroundTertiary, in: Capsule())
            .overlay(Capsule().stroke(isSelected ? DS.ColorToken.accent : DS.ColorToken.separator, lineWidth: 1))
    }
}

struct DSCaptureToast: View {
    let text: String

    var body: some View {
        Text(text)
            .font(DS.TypeScale.bodyEmphasis)
            .foregroundStyle(DS.ColorToken.onAccent)
            .padding(.horizontal, DS.Space.screenHorizontal)
            .padding(.vertical, 11)
            .background(Capsule().fill(DS.ColorToken.accent))
            .overlay(Capsule().stroke(DS.ColorToken.separator.opacity(0.35), lineWidth: 1))
            .shadow(color: DS.Shadow.card.color, radius: DS.Shadow.card.radius, x: 0, y: DS.Shadow.card.y)
    }
}

/// Styled in-app prompt for capture flow (duplicate UPC) — avoids stacked UIKit alerts.
struct CaptureFlowPromptOverlay: View {
    let icon: String
    let iconColor: Color
    let title: String
    let message: String
    let primaryTitle: String
    var primaryRole: ButtonRole?
    let secondaryTitle: String
    var secondaryRole: ButtonRole?
    let cancelTitle: String
    let onPrimary: () -> Void
    let onSecondary: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.52)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            DSCard {
                VStack(spacing: DS.Space.stack + 2) {
                    Image(systemName: icon)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(iconColor)
                        .padding(.top, DS.Space.tight)

                    Text(title)
                        .font(DS.TypeScale.sectionTitle)
                        .foregroundStyle(DS.ColorToken.label)
                        .multilineTextAlignment(.center)

                    Text(message)
                        .font(DS.TypeScale.caption)
                        .foregroundStyle(DS.ColorToken.secondaryLabel)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: DS.Space.stack - 2) {
                        if primaryRole == .destructive {
                            Button(primaryTitle, role: primaryRole, action: onPrimary)
                                .buttonStyle(SecondaryButtonStyle())
                                .foregroundStyle(Color.red)
                        } else {
                            Button(primaryTitle, role: primaryRole, action: onPrimary)
                                .buttonStyle(PrimaryButtonStyle())
                        }
                        Button(secondaryTitle, role: secondaryRole, action: onSecondary)
                            .buttonStyle(SecondaryButtonStyle())
                        Button(cancelTitle, action: onCancel)
                            .font(DS.TypeScale.caption.weight(.semibold))
                            .foregroundStyle(DS.ColorToken.secondaryLabel)
                            .padding(.top, DS.Space.tight)
                    }
                }
            }
            .padding(.horizontal, DS.Space.screenHorizontal)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .zIndex(20)
    }
}

/// Action-oriented capture tips for Single Product and Batch workspaces.
enum CaptureStudioGuidelines {
    static let bullets: [String] = [
        "💡 Ensure your subject is placed in a well-lit space under clean, bright overhead lighting.",
        "📸 Hold the camera steady with both hands—do not shake the device during capture.",
        "🧼 Position your items against clutter-free surfaces to ensure crisp subject edge detection.",
    ]
}

struct DSStudioGuidelinesPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.stack) {
            Label("Studio Guidelines", systemImage: "lightbulb.min")
                .font(DS.TypeScale.dockSection)
                .foregroundStyle(DS.ColorToken.label)

            VStack(alignment: .leading, spacing: DS.Space.tight + 2) {
                ForEach(Array(CaptureStudioGuidelines.bullets.enumerated()), id: \.offset) { _, bullet in
                    Text(bullet)
                        .font(DS.TypeScale.caption)
                        .foregroundStyle(DS.ColorToken.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(DS.Space.cardPadding + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.ColorToken.backgroundSecondary, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .stroke(DS.ColorToken.separator, lineWidth: 1)
        )
    }
}

/// Compact contextual info — tap for a short popover beside the control.
struct DSInlineHelpButton: View {
    let message: String
    var accessibilityTitle: String = "Info"

    @State private var showsTip = false

    var body: some View {
        Button {
            showsTip = true
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(DS.ColorToken.accent)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plainPressable)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityHint(message)
        .popover(isPresented: $showsTip, arrowEdge: .top) {
            Text(message)
                .font(DS.TypeScale.caption)
                .foregroundStyle(DS.ColorToken.label)
                .lineLimit(6)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(DS.Space.cardPadding)
                .frame(maxWidth: 300, alignment: .leading)
                .presentationCompactAdaptation(.popover)
        }
    }
}

/// Primary/secondary dashboard action with trailing contextual help.
struct DSDashboardActionRow<Content: View>: View {
    let helpMessage: String
    var helpAccessibilityTitle: String = "Info"
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.tight) {
            content()
                .frame(maxWidth: .infinity)
            DSInlineHelpButton(message: helpMessage, accessibilityTitle: helpAccessibilityTitle)
        }
    }
}

// MARK: - Preview chrome (Photos-style dock)

/// Semantic colors for badges drawn on top of arbitrary photos (high contrast).
enum DSPhotoOverlay {
    /// Fixed dark scrim keeps badge text readable on any photo pixels.
    static let scrim = Color.black.opacity(0.56)
    /// Light text on the fixed dark scrim (media chrome exception — not sheet UI).
    static let primaryText = Color(.systemBackground)
    static let secondaryText = Color(.systemBackground).opacity(0.88)
    static let stroke = Color(.systemBackground).opacity(0.22)
}

struct DSPreviewDockTray<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        DSCard(padding: DS.Space.stack) {
            content()
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, DS.Space.screenHorizontal - 6)
        .padding(.top, DS.Space.tight)
        .safeAreaPadding(.bottom, DS.Space.tight)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                DS.ColorToken.backgroundSecondary
                Rectangle().fill(.ultraThinMaterial)
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }
}

/// Single-line dock hint above the preview filmstrip — scales down before wrapping.
struct PreviewDockSubtitleText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(DS.TypeScale.micro.weight(.medium))
            .foregroundStyle(DS.ColorToken.secondaryLabel)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .truncationMode(.tail)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}

/// One continuous material pill for the preview top icon row — icons inside stay background-free.
struct DSPreviewFloatingToolbar<Content: View>: View {
    var horizontalPadding: CGFloat = 14
    var verticalPadding: CGFloat = 8
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity, alignment: .center)
            .background {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(DS.ColorToken.separator.opacity(0.55), lineWidth: 0.5)
            }
    }
}

extension View {
    /// Plain SF Symbol tap target — fixed square slot for aligned preview toolbar rows.
    func previewToolbarIconSlot(side: CGFloat = 38) -> some View {
        frame(width: side, height: side, alignment: .center)
            .contentShape(Rectangle())
    }
}

/// Consistent SF Symbol cell for the preview top icon tray.
struct PreviewToolbarIconLabel: View {
    let systemName: String
    var side: CGFloat = 38
    var symbolSize: CGFloat = 17

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: symbolSize, weight: .medium))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(DS.ColorToken.accent)
            .previewToolbarIconSlot(side: side)
    }
}

struct DSPhotoOverlayBadge: View {
    let text: String
    var multiline: Bool = false
    var highlighted: Bool = false
    /// Light pill with dark text (live-preview status below the top toolbar).
    var lightSurface: Bool = false

    var body: some View {
        Text(text)
            .font(DS.TypeScale.micro)
            .foregroundStyle(foregroundColor)
            .lineLimit(multiline ? 2 : 1)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
    }

    private var foregroundColor: Color {
        if lightSurface { return DS.ColorToken.label }
        if highlighted { return DS.ColorToken.accent }
        return DSPhotoOverlay.primaryText
    }

    private var backgroundColor: Color {
        lightSurface ? Color(.systemBackground).opacity(0.92) : DSPhotoOverlay.scrim
    }

    private var borderColor: Color {
        if lightSurface { return DS.ColorToken.separator }
        if highlighted { return DS.ColorToken.accent.opacity(0.6) }
        return DSPhotoOverlay.stroke
    }
}

struct DSPreviewToolbarIconButton: View {
    let systemName: String
    var label: String?
    var action: (() -> Void)?

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    iconLabel
                }
                .buttonStyle(FeedbackPressButtonStyle(pressedScale: DS.Motion.pressScaleCompact))
            } else {
                iconLabel
            }
        }
    }

    @ViewBuilder
    private var iconLabel: some View {
        Group {
            if let label {
                VStack(spacing: 2) {
                    Image(systemName: systemName)
                        .font(DS.TypeScale.sectionTitle.weight(.medium))
                    Text(label)
                        .font(DS.TypeScale.micro.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .truncationMode(.tail)
                        .allowsTightening(true)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
            } else {
                Image(systemName: systemName)
                    .font(DS.TypeScale.bodyEmphasis)
            }
        }
        .foregroundStyle(DS.ColorToken.label)
    }
}

/// Preview dock control — matches dashboard secondary chip weight.
struct GlassPreviewButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(DS.ColorToken.label)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                        .fill(DS.ColorToken.backgroundTertiary.opacity(configuration.isPressed ? 0.5 : 0.65))
                    RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    .stroke(DS.ColorToken.separator, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? DS.Motion.pressScaleCompact : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(DS.Motion.pressSpring, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { InteractionHaptics.tapPreferringSettings() }
            }
    }
}

struct DSFloatingChromeButton: View {
    let systemName: String
    let accessibilityLabel: String
    let action: () -> Void

    @State private var bounceTrigger = 0

    var body: some View {
        Button {
            bounceTrigger += 1
            TapFeedback.run { action() }
        } label: {
            Image(systemName: systemName)
                .font(DS.TypeScale.bodyEmphasis)
                .foregroundStyle(DS.ColorToken.accent)
                .symbolEffect(.bounce, value: bounceTrigger)
                .frame(width: 38, height: 38)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(DS.ColorToken.separator, lineWidth: 1))
        }
        .buttonStyle(FeedbackPressButtonStyle(pressedScale: DS.Motion.pressScaleIcon, playsHaptic: false))
        .accessibilityLabel(accessibilityLabel)
    }
}
