import SwiftUI
import UIKit

// MARK: - Two-color brand (charcoal + mint) on system light / dark chrome

enum BrandPalette {
    /// Structural / charcoal — buttons & links in light mode, label on mint in dark mode.
    static let charcoal = "#283F3B"
    /// Accent / mint — highlights, selection, buttons in dark mode.
    static let mint = "#99DDC8"

    // Light surfaces — clear separation from white chrome
    static let lightBackground = "#FFFFFF"
    static let lightCard = "#F2F2F7"
    static let lightSurface = "#E8E8ED"
    static let lightBorder = "#D1D1D6"

    // Dark surfaces — soft gray (not pure black)
    static let darkBackground = "#1C1C1E"
    static let darkSurface = "#2C2C2E"
    /// Queue rows & elevated cards in dark mode.
    static let darkCard = "#4A4A4A"
    static let darkBorder = "#5C5C5E"

    // Legacy aliases used across the app
    static let primary = charcoal
    static let softGold = mint
    static let accentSky = mint
}

struct AppTheme {
    static let charcoal = Color(hex: BrandPalette.charcoal)
    static let mint = Color(hex: BrandPalette.mint)

    /// Light: charcoal. Dark: mint.
    static let primary = charcoal
    static let accent = mint

    // Back-compat names
    static let forestPrimary = charcoal
    static let forestDeep = charcoal
    static let softGold = mint
    static let brightGold = mint
    static let gold = mint
    static let warmCream = Color(uiColor: .label)
    static let sageAccent = mint
    static let mossGray = Color(uiColor: .secondaryLabel)
    static let deepNavy = charcoal
    static let indigo = charcoal

    // Semantic system surfaces (dynamic light / dark)
    static let background = DS.ColorToken.background
    static let backgroundSecondary = DS.ColorToken.backgroundSecondary
    static let elevatedSurface = DS.ColorToken.backgroundTertiary
    static let card = DS.ColorToken.backgroundSecondary
    static let surface = DS.ColorToken.backgroundTertiary
    static let strongerSurface = DS.ColorToken.groupedSecondary
    static let border = DS.ColorToken.separator

    static let primaryText = DS.ColorToken.label
    static let secondaryText = DS.ColorToken.secondaryLabel
    static let tertiaryText = DS.ColorToken.tertiaryLabel

    /// Toolbar icons, links — charcoal on light, mint on dark.
    static let accentText = brandAccent

    /// Use `DS.ColorToken.label` on menu/picker surfaces — not brand accent (low contrast on dark fills).
    static let pickerSelectedText = DS.ColorToken.label

    static let charcoalBackground = background
    static let softText = secondaryText

    static let infoSurface = DS.ColorToken.groupedSecondary

    static let success = DS.ColorToken.success
    static let warning = DS.ColorToken.warning
    static let error = DS.ColorToken.error
    static let info = brandAccent

    static let glassTint = mint.opacity(0.12)
    static let goldBorderGlow = mint.opacity(0.28)
    static let ambientShadow = DS.ColorToken.elevatedShadow

    static var forestGradient: LinearGradient { brandGradient }
    static var emeraldSuccessGradient: LinearGradient { brandGradient }
    static var emeraldGoldGradient: LinearGradient { brandGradient }
    static var premiumGoldGradient: LinearGradient { brandGradient }
    static var sageEmeraldGradient: LinearGradient { brandGradient }
    static var luxuryHeroGradient: LinearGradient { brandGradient }

    static var brandGradient: LinearGradient {
        LinearGradient(
            colors: [charcoal.opacity(0.15), mint.opacity(0.12)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Mint on dark backgrounds, charcoal on light.
    static var brandAccent: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: BrandPalette.mint)
                : UIColor(hex: BrandPalette.charcoal)
        })
    }

    /// Filled primary control: charcoal (light) or mint (dark).
    static func primaryFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? mint : charcoal
    }

    static func onPrimaryLabel(for scheme: ColorScheme) -> Color {
        scheme == .dark ? charcoal : .white
    }

    /// Waiting overlays, launch screen, import progress.
    static let brandPanelFill = Color(hex: BrandPalette.charcoal).opacity(0.94)
    static let brandPanelTitle = Color(hex: BrandPalette.mint)
    static let brandPanelBody = Color.white.opacity(0.92)
    static let brandScrim = Color.black.opacity(0.45)

    private static func adaptive(light: String, dark: String) -> Color {
        Color(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension Color {
    init(hex: String) {
        self.init(UIColor(hex: hex))
    }
}

extension UIColor {
    convenience init(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r, g, b, a: CGFloat
        switch cleaned.count {
        case 8:
            r = CGFloat((value & 0xFF00_0000) >> 24) / 255
            g = CGFloat((value & 0x00FF_0000) >> 16) / 255
            b = CGFloat((value & 0x0000_FF00) >> 8) / 255
            a = CGFloat(value & 0x0000_00FF) / 255
        default:
            r = CGFloat((value & 0xFF0000) >> 16) / 255
            g = CGFloat((value & 0x00FF00) >> 8) / 255
            b = CGFloat(value & 0x0000FF) / 255
            a = 1
        }
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}

enum AppTypography {
    static let screenTitle = DS.TypeScale.screenTitle
    static let pageTitle = DS.TypeScale.pageTitle
    static let sectionTitle = DS.TypeScale.sectionTitle
    static let rowTitle = DS.TypeScale.rowTitle
    static let rowMeta = DS.TypeScale.caption
    static let body = DS.TypeScale.body
    static let bodyEmphasis = DS.TypeScale.bodyEmphasis
    static let caption = DS.TypeScale.caption
    static let micro = DS.TypeScale.micro
}

enum AppLayout {
    static let screenHorizontal = DS.Space.screenHorizontal
    static let cardCorner = DS.Radius.card
    static let queueRowCorner = DS.Radius.queueRow
    static let listRowSpacing = DS.Space.listRowSpacing
    static let listRowInsetH = DS.Space.listRowInsetH
}

/// Photo canvas behind the product in the queue preview editor.
enum PreviewChrome {
    static func canvasBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? DS.ColorToken.background : DS.ColorToken.backgroundSecondary
    }

    static func pageBackground(for scheme: ColorScheme) -> Color {
        DS.ColorToken.background
    }

    static func toolbarIcon(for scheme: ColorScheme) -> Color {
        DS.ColorToken.accent
    }
}

/// Labels on the preview bottom dock — semantic text on frosted chrome.
enum PreviewDockChrome {
    static let primaryLabel = DS.ColorToken.label
    static let secondaryLabel = DS.ColorToken.secondaryLabel
    static let tertiaryLabel = DS.ColorToken.tertiaryLabel
    static let sliderTint = AppTheme.brandAccent
    static let chipFillUnselected = DS.ColorToken.backgroundTertiary
    static let chipFillSelected = AppTheme.brandAccent.opacity(0.28)
    static let chipTextUnselected = primaryLabel
    static let chipTextSelected = DS.ColorToken.onAccent
    static let buttonStroke = DS.ColorToken.separator
}

/// UIKit markup chrome — forwards to `DSUIKit` / global sheet tokens.
enum MarkupEditorChromeUIKit {
    static func pageBackground(_ traits: UITraitCollection) -> UIColor {
        DSUIKit.pageBackground(traits)
    }

    static func panelBackground(_ traits: UITraitCollection) -> UIColor {
        DSUIKit.panelBackground
    }

    static func dockBackground(_ traits: UITraitCollection) -> UIColor {
        DSUIKit.panelBackground
    }

    static func primaryText(_ traits: UITraitCollection) -> UIColor {
        DSUIKit.label
    }

    static func secondaryText(_ traits: UITraitCollection) -> UIColor {
        DSUIKit.secondaryLabel
    }

    static func chipBackground(_ traits: UITraitCollection) -> UIColor {
        DSUIKit.chipBackground
    }

    static func chipSelected(_ traits: UITraitCollection) -> UIColor {
        DSUIKit.chipSelectedBackground(traits)
    }

    static func divider(_ traits: UITraitCollection) -> UIColor {
        DSUIKit.separator
    }

    static func accent(_ traits: UITraitCollection) -> UIColor {
        DSUIKit.accent(traits)
    }

    static func headerActionText(_ traits: UITraitCollection) -> UIColor {
        DSUIKit.accent(traits)
    }

    static func subsheetSurface(_ traits: UITraitCollection) -> UIColor {
        DSUIKit.panelBackground
    }

    static func controlLabel(_ traits: UITraitCollection) -> UIColor {
        DSUIKit.label
    }

    static func captionLabel(_ traits: UITraitCollection) -> UIColor {
        DSUIKit.secondaryLabel
    }

    static func sliderTint(_ traits: UITraitCollection) -> UIColor {
        DSUIKit.accent(traits)
    }
}

struct PreviewDockBackground: View {
    var body: some View {
        ZStack {
            DS.ColorToken.backgroundSecondary
            Rectangle().fill(.ultraThinMaterial)
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

struct EditorPanelActionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(DS.TypeScale.caption.weight(.semibold))
            .foregroundStyle(DS.ColorToken.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Space.cardPadding)
            .padding(.vertical, 9)
            .background(DS.ColorToken.backgroundTertiary, in: RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                    .stroke(DS.ColorToken.separator, lineWidth: 1)
            )
    }
}

struct HelperInfoBox: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.stack) {
            Image(systemName: "info.circle.fill")
                .font(DS.TypeScale.bodyEmphasis)
                .foregroundStyle(DS.ColorToken.accent)
            Text(text)
                .font(DS.TypeScale.caption)
                .foregroundStyle(DS.ColorToken.label)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.Space.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.ColorToken.groupedSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                .stroke(DS.ColorToken.separator, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))
    }
}

struct LiquidGlassChip<Content: View>: View {
    var cornerRadius: CGFloat = 12
    var horizontalPadding: CGFloat = 10
    var verticalPadding: CGFloat = 5
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(AppTheme.glassTint)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppTheme.goldBorderGlow, lineWidth: 1)
            )
            .shadow(color: AppTheme.ambientShadow, radius: 6, x: 0, y: 2)
    }
}

extension View {
    func liquidGlassChip(corner: CGFloat = 12, hPad: CGFloat = 10, vPad: CGFloat = 5) -> some View {
        LiquidGlassChip(cornerRadius: corner, horizontalPadding: hPad, verticalPadding: vPad) { self }
    }
}

extension ToolbarContent {
    /// Suppresses iOS 26 shared liquid-glass chrome on toolbar items (avoids “visual style… returning nil” spam).
    @ToolbarContentBuilder
    func dsHideToolbarSharedBackground() -> some ToolbarContent {
        if #available(iOS 26.0, *) {
            self.sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

struct IconBadge: View {
    let systemName: String
    var dimension: CGFloat = 40
    var iconFontSize: CGFloat = 17

    private var radius: CGFloat { dimension * 0.29 }

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: iconFontSize, weight: .semibold))
            .foregroundStyle(AppTheme.brandAccent)
            .frame(width: dimension, height: dimension)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonStyleBody(configuration: configuration, colorScheme: colorScheme, vibrate: InteractionHaptics.vibrateEnabledFromSettings)
    }
}

private struct PrimaryButtonStyleBody: View {
    let configuration: ButtonStyleConfiguration
    let colorScheme: ColorScheme
    let vibrate: Bool

    var body: some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .foregroundStyle(AppTheme.onPrimaryLabel(for: colorScheme))
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    .fill(AppTheme.primaryFill(for: colorScheme).opacity(configuration.isPressed ? 0.82 : 1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? DS.Motion.pressScale : 1)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(DS.Motion.pressSpring, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { InteractionHaptics.tap(vibrate: vibrate) }
            }
    }
}

struct SecondaryButtonStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        SecondaryButtonStyleBody(configuration: configuration, vibrate: InteractionHaptics.vibrateEnabledFromSettings)
    }
}

private struct SecondaryButtonStyleBody: View {
    let configuration: ButtonStyleConfiguration
    let vibrate: Bool

    var body: some View {
        configuration.label
            .font(.system(size: 16, weight: .medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .foregroundStyle(DS.ColorToken.label)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    .fill(DS.ColorToken.backgroundTertiary.opacity(configuration.isPressed ? 0.72 : 1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    .stroke(DS.ColorToken.separator, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? DS.Motion.pressScale : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(DS.Motion.pressSpring, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { InteractionHaptics.tap(vibrate: vibrate) }
            }
    }
}

struct CompactSecondaryButtonStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        CompactSecondaryButtonStyleBody(configuration: configuration, vibrate: InteractionHaptics.vibrateEnabledFromSettings)
    }
}

private struct CompactSecondaryButtonStyleBody: View {
    let configuration: ButtonStyleConfiguration
    let vibrate: Bool

    var body: some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .minimumScaleFactor(0.82)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .foregroundStyle(AppTheme.primaryText)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.compactControl, style: .continuous)
                    .fill(configuration.isPressed ? AppTheme.surface.opacity(0.85) : AppTheme.card)
            )
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.compactControl, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? DS.Motion.pressScale : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(DS.Motion.pressSpring, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { InteractionHaptics.tap(vibrate: vibrate) }
            }
    }
}

struct DangerButtonStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        DangerButtonStyleBody(configuration: configuration, vibrate: InteractionHaptics.vibrateEnabledFromSettings)
    }
}

private struct DangerButtonStyleBody: View {
    let configuration: ButtonStyleConfiguration
    let vibrate: Bool

    var body: some View {
        configuration.label
            .font(.system(size: 16, weight: .medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(AppTheme.error.opacity(configuration.isPressed ? 0.2 : 0.1))
            .foregroundStyle(AppTheme.error)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    .stroke(AppTheme.error.opacity(0.4), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
            .scaleEffect(configuration.isPressed ? DS.Motion.pressScale : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(DS.Motion.pressSpring, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { InteractionHaptics.tap(vibrate: vibrate) }
            }
    }
}

struct CompactPrimaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        CompactPrimaryButtonStyleBody(configuration: configuration, colorScheme: colorScheme, vibrate: InteractionHaptics.vibrateEnabledFromSettings)
    }
}

private struct CompactPrimaryButtonStyleBody: View {
    let configuration: ButtonStyleConfiguration
    let colorScheme: ColorScheme
    let vibrate: Bool

    var body: some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .minimumScaleFactor(0.82)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .padding(.horizontal, 8)
            .foregroundStyle(AppTheme.onPrimaryLabel(for: colorScheme))
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.compactControl, style: .continuous)
                    .fill(AppTheme.primaryFill(for: colorScheme).opacity(configuration.isPressed ? 0.82 : 1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.compactControl, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? DS.Motion.pressScale : 1)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(DS.Motion.pressSpring, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { InteractionHaptics.tap(vibrate: vibrate) }
            }
    }
}

struct CompactDangerButtonStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        CompactDangerButtonStyleBody(configuration: configuration, vibrate: InteractionHaptics.vibrateEnabledFromSettings)
    }
}

private struct CompactDangerButtonStyleBody: View {
    let configuration: ButtonStyleConfiguration
    let vibrate: Bool

    var body: some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .minimumScaleFactor(0.82)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .padding(.horizontal, 8)
            .background(AppTheme.error.opacity(configuration.isPressed ? 0.2 : 0.1))
            .foregroundStyle(AppTheme.error)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.compactControl, style: .continuous)
                    .stroke(AppTheme.error.opacity(0.4), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.compactControl, style: .continuous))
            .scaleEffect(configuration.isPressed ? DS.Motion.pressScale : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(DS.Motion.pressSpring, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { InteractionHaptics.tap(vibrate: vibrate) }
            }
    }
}

struct HomeToolbarButton: View {
    @Environment(\.dismiss) private var dismiss
    var action: (() -> Void)?

    var body: some View {
        Button {
            InteractionHaptics.tap(vibrate: InteractionHaptics.vibrateEnabledFromSettings)
            if let action { action() } else { dismiss() }
        } label: {
            Label("Home", systemImage: "house.fill")
                .labelStyle(.iconOnly)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.brandAccent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .liquidGlassChip(corner: DS.Radius.control, hPad: 0, vPad: 0)
        }
        .buttonStyle(FeedbackPressButtonStyle(pressedScale: DS.Motion.pressScaleIcon, playsHaptic: false))
        .accessibilityLabel("Go to Home")
    }
}

struct HomeShortcutToolbar: ViewModifier {
    var popToRoot: () -> Void

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    InteractionHaptics.tap(vibrate: InteractionHaptics.vibrateEnabledFromSettings)
                    popToRoot()
                } label: {
                    Label("Home", systemImage: "house.fill")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.brandAccent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .liquidGlassChip(corner: DS.Radius.control, hPad: 0, vPad: 0)
                }
                .buttonStyle(FeedbackPressButtonStyle(pressedScale: DS.Motion.pressScaleIcon, playsHaptic: false))
                .accessibilityLabel("Go to Home")
            }
        }
    }
}

extension View {
    func homeShortcutToolbar(popToRoot: @escaping () -> Void) -> some View {
        modifier(HomeShortcutToolbar(popToRoot: popToRoot))
    }
}

/// Restores the native left-edge swipe-to-go-back gesture on pushed views even though our routes hide
/// the system navigation bar (which normally disables `interactivePopGestureRecognizer`). The
/// `viewControllers.count > 1` guard keeps it from firing on the root dashboard.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    open override func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}

/// Soft brand lighting on grouped gray backgrounds (charcoal + mint).
struct PremiumBackgroundView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            AppTheme.background

            if colorScheme == .dark {
                LinearGradient(
                    colors: [Color(hex: BrandPalette.darkBackground), AppTheme.charcoal.opacity(0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                RadialGradient(
                    colors: [AppTheme.mint.opacity(0.16), .clear],
                    center: .topTrailing,
                    startRadius: 12,
                    endRadius: 400
                )
                RadialGradient(
                    colors: [AppTheme.charcoal.opacity(0.28), .clear],
                    center: .bottomLeading,
                    startRadius: 8,
                    endRadius: 320
                )
            } else {
                LinearGradient(
                    colors: [Color(hex: BrandPalette.lightBackground), Color(hex: BrandPalette.lightCard)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                RadialGradient(
                    colors: [AppTheme.mint.opacity(0.10), .clear],
                    center: .topTrailing,
                    startRadius: 10,
                    endRadius: 340
                )
            }
        }
        .ignoresSafeArea()
    }
}

enum CanvasStyleGradientFill {
    static func shape(style: BackgroundCanvasStyle, colors: [Color]) -> some ShapeStyle {
        let palette = colors.isEmpty ? [Color.white] : colors
        if style.usesRadialBlendPreview {
            return AnyShapeStyle(
                RadialGradient(
                    colors: palette.count >= 2 ? palette : palette + [.white],
                    center: UnitPoint(x: 0.5, y: 0.38),
                    startRadius: 2,
                    endRadius: 120
                )
            )
        }
        return AnyShapeStyle(
            LinearGradient(
                colors: palette,
                startPoint: style.usesDiagonalBlendAxis ? .topLeading : .top,
                endPoint: style.usesDiagonalBlendAxis ? .bottomTrailing : .bottom
            )
        )
    }
}

extension AppTheme {
    static var darkCardUIColor: UIColor { UIColor(hex: BrandPalette.darkCard) }

    static var chromeBarUIColor: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: BrandPalette.darkCard)
                : UIColor(hex: BrandPalette.lightSurface)
        }
    }

    static var primaryUIColor: UIColor { UIColor(hex: BrandPalette.charcoal) }
    static var accentUIColor: UIColor { UIColor(hex: BrandPalette.mint) }
}
