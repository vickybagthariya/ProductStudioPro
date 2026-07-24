import SwiftUI
import UIKit
import PencilKit

/// PencilKit markup with system tool picker. Saving uses SwiftUI `dismiss` only.
struct MarkupEditorSheet: View {
    let baseImage: UIImage
    var onSave: (UIImage) -> Void
    var onDiscard: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        MarkupEditorBridge(
            baseImage: baseImage,
            onSave: { merged in
                onSave(merged)
                dismiss()
            },
            onDiscard: {
                onDiscard()
                dismiss()
            }
        )
        .ignoresSafeArea()
    }
}

struct MarkupEditorBridge: UIViewControllerRepresentable {
    let baseImage: UIImage
    let onSave: (UIImage) -> Void
    let onDiscard: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSave: onSave, onDiscard: onDiscard)
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let root = MarkupViewController()
        root.coordinator = context.coordinator
        root.baseImage = baseImage
        let nav = UINavigationController(rootViewController: root)
        nav.modalPresentationStyle = .fullScreen
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    final class Coordinator {
        let onSave: (UIImage) -> Void
        let onDiscard: () -> Void
        init(onSave: @escaping (UIImage) -> Void, onDiscard: @escaping () -> Void) {
            self.onSave = onSave
            self.onDiscard = onDiscard
        }
    }
}

// MARK: - Geometry helpers

private func aspectFitRect(imageSize: CGSize, in rect: CGRect) -> CGRect {
    guard imageSize.width > 1, imageSize.height > 1 else { return rect }
    let ws = rect.width / imageSize.width
    let hs = rect.height / imageSize.height
    let s = min(ws, hs)
    let w = imageSize.width * s
    let h = imageSize.height * s
    return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
}

private func flipImageHorizontally(_ image: UIImage) -> UIImage {
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = image.scale
    format.opaque = false
    let r = UIGraphicsImageRenderer(size: image.size, format: format)
    return r.image { ctx in
        let c = ctx.cgContext
        c.translateBy(x: image.size.width, y: 0)
        c.scaleBy(x: -1, y: 1)
        image.draw(in: CGRect(origin: .zero, size: image.size))
    }
}

private final class MarkupPassthroughOverlay: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled, !isHidden, alpha >= 0.01 else { return nil }
        guard bounds.contains(point) else { return nil }
        for subview in subviews.reversed() {
            let sp = subview.convert(point, from: self)
            if let hit = subview.hitTest(sp, with: event) { return hit }
        }
        return nil
    }
}

// MARK: - Text color / box fill presets (Canva-style)

private enum MarkupColorPickTarget {
    case text
    case textGradientEnd
    case textOutline
    case boxPrimary
    case boxSecondary
}

private enum MarkupTextColorPresets {
    static let textGradients: [(String, UIColor, UIColor)] = [
        ("Sunset", UIColor(hexString: "#FF6B6B") ?? .orange, UIColor(hexString: "#FFE66D") ?? .yellow),
        ("Ocean", UIColor(hexString: "#2193B0") ?? .cyan, UIColor(hexString: "#6DD5ED") ?? .systemTeal),
        ("Berry", UIColor(hexString: "#8E2DE2") ?? .purple, UIColor(hexString: "#FF6FD8") ?? .systemPink),
        ("Forest", UIColor(hexString: "#11998E") ?? .green, UIColor(hexString: "#38EF7D") ?? .systemGreen),
        ("Fire", UIColor(hexString: "#FF512F") ?? .orange, UIColor(hexString: "#F09819") ?? .yellow),
        ("Aurora", UIColor(hexString: "#00C9FF") ?? .cyan, UIColor(hexString: "#92FE9D") ?? .green),
        ("Royal", UIColor(hexString: "#141E30") ?? .black, UIColor(hexString: "#243B55") ?? .darkGray),
        ("Rose Gold", UIColor(hexString: "#B76E79") ?? .systemPink, UIColor(hexString: "#FFD1DC") ?? .systemPink),
        ("Mono", .white, UIColor(white: 0.72, alpha: 1)),
        ("Ink", UIColor(hexString: "#0F2027") ?? .black, UIColor(hexString: "#2C5364") ?? .gray),
        ("Coral", UIColor(hexString: "#FF9B85") ?? .systemPink, UIColor(hexString: "#FF6B6B") ?? .red),
        ("Lavender", UIColor(hexString: "#CE93D8") ?? .systemPurple, UIColor(hexString: "#6A1B9A") ?? .purple),
        ("Gold", UIColor(hexString: "#FFF4D6") ?? .white, UIColor(hexString: "#C9A227") ?? .yellow),
        ("Neon", UIColor(hexString: "#7026C5") ?? .purple, UIColor(hexString: "#E03BFF") ?? .magenta),
        ("Mint Fade", UIColor(hexString: "#283F3B") ?? .darkGray, UIColor(hexString: "#99DDC8") ?? .systemTeal),
        ("Peach", UIColor(hexString: "#FFF8F2") ?? .white, UIColor(hexString: "#E8A598") ?? .systemPink),
    ]

    static let boxGradients: [(String, UIColor, UIColor)] = [
        ("Dark", UIColor(hexString: "#0E111A") ?? .black, UIColor(hexString: "#2A3358") ?? .darkGray),
        ("Slate", UIColor(hexString: "#37474F") ?? .gray, UIColor(hexString: "#78909C") ?? .lightGray),
        ("Warm", UIColor(hexString: "#BF360C") ?? .brown, UIColor(hexString: "#FF8F00") ?? .orange),
        ("Cool", UIColor(hexString: "#0D47A1") ?? .blue, UIColor(hexString: "#29B6F6") ?? .cyan),
        ("Glass", UIColor(white: 1, alpha: 0.18), UIColor(white: 1, alpha: 0.06)),
        ("Mint", UIColor(hexString: "#283F3B") ?? .darkGray, UIColor(hexString: "#99DDC8") ?? .systemTeal),
        ("Night", UIColor(hexString: "#0F0C29") ?? .black, UIColor(hexString: "#302B63") ?? .purple),
        ("Sunrise", UIColor(hexString: "#FF512F") ?? .orange, UIColor(hexString: "#DD2476") ?? .systemPink),
        ("Ocean", UIColor(hexString: "#134E5E") ?? .systemTeal, UIColor(hexString: "#71B280") ?? .green),
        ("Smoke", UIColor(hexString: "#1A1A1E") ?? .black, UIColor(hexString: "#5A5A68") ?? .gray),
        ("Wine", UIColor(hexString: "#880E4F") ?? .systemPink, UIColor(hexString: "#EC407A") ?? .systemPink),
        ("Forest", UIColor(hexString: "#1B5E20") ?? .green, UIColor(hexString: "#7CB342") ?? .green),
        ("Sand", UIColor(hexString: "#FFF3E0") ?? .white, UIColor(hexString: "#E8C9A0") ?? .brown),
        ("Blush", UIColor(hexString: "#FCE4EC") ?? .white, UIColor(hexString: "#F8BBD0") ?? .systemPink),
        ("Violet", UIColor(hexString: "#2A114A") ?? .purple, UIColor(hexString: "#E03BFF") ?? .magenta),
        ("Aurora", UIColor(hexString: "#0B1026") ?? .black, UIColor(hexString: "#00C9B7") ?? .cyan),
    ]
}

private func markupGradientPatternColor(size: CGSize, start: UIColor, end: UIColor) -> UIColor {
    guard size.width > 2, size.height > 2 else { return start }
    let format = UIGraphicsImageRendererFormat()
    format.scale = UIScreen.main.scale
    format.opaque = false
    let img = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
        let colors = [start.cgColor, end.cgColor] as CFArray
        let space = CGColorSpaceCreateDeviceRGB()
        if let g = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
            ctx.cgContext.drawLinearGradient(
                g,
                start: CGPoint(x: 0, y: size.height / 2),
                end: CGPoint(x: size.width, y: size.height / 2),
                options: []
            )
        }
    }
    return UIColor(patternImage: img)
}

// MARK: - Canva-style text toolbar UI

private final class CanvaToolbarButton: UIButton {
    var isCanvaSelected = false {
        didSet { refreshChrome() }
    }

    private var traits = UITraitCollection.current

    init(symbol: String, accessibility: String) {
        super.init(frame: .zero)
        let img = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
        setImage(img, for: .normal)
        layer.cornerRadius = DS.Radius.chip
        layer.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false
        accessibilityLabel = accessibility
        heightAnchor.constraint(equalToConstant: 36).isActive = true
        widthAnchor.constraint(equalToConstant: 36).isActive = true
        refreshChrome()
        DSUIKit.installPressFeedback(on: self, scale: DS.Motion.pressScaleIcon)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func applyTraits(_ traits: UITraitCollection) {
        self.traits = traits
        refreshChrome()
    }

    private func refreshChrome() {
        tintColor = MarkupEditorChromeUIKit.primaryText(traits)
        backgroundColor = isCanvaSelected
            ? MarkupEditorChromeUIKit.chipSelected(traits)
            : MarkupEditorChromeUIKit.chipBackground(traits)
        layer.borderWidth = isCanvaSelected ? 1.5 : 0
        layer.borderColor = MarkupEditorChromeUIKit.accent(traits).cgColor
    }
}

private final class CanvaColorSwatchButton: UIControl {
    let swatch = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        swatch.isUserInteractionEnabled = false
        swatch.layer.cornerRadius = DS.Radius.control
        swatch.layer.borderWidth = 2
        swatch.layer.borderColor = MarkupEditorChromeUIKit.divider(traitCollection).cgColor
        swatch.translatesAutoresizingMaskIntoConstraints = false
        addSubview(swatch)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 44),
            widthAnchor.constraint(equalToConstant: 44),
            swatch.centerXAnchor.constraint(equalTo: centerXAnchor),
            swatch.centerYAnchor.constraint(equalTo: centerYAnchor),
            swatch.widthAnchor.constraint(equalToConstant: 28),
            swatch.heightAnchor.constraint(equalToConstant: 28),
        ])
        DSUIKit.installPressFeedback(on: self, scale: DS.Motion.pressScaleCompact)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func setColor(_ color: UIColor) {
        swatch.backgroundColor = color
    }

    func applyTraits(_ traits: UITraitCollection) {
        swatch.layer.borderColor = MarkupEditorChromeUIKit.divider(traits).cgColor
    }
}

/// Compact Canva-style toolbar — each chip opens a sub-sheet on the host.
final class MarkupCanvaTextToolbar: UIView {
    weak var host: MarkupViewController?

    private let fontChip = UIButton(type: .system)
    private let sizeChip = UIButton(type: .system)
    private let colorsChip = UIButton(type: .system)
    private let alignChip = UIButton(type: .system)
    private let spacingChip = UIButton(type: .system)
    private let boldBtn = CanvaToolbarButton(symbol: "bold", accessibility: "Bold")
    private let italicBtn = CanvaToolbarButton(symbol: "italic", accessibility: "Italic")
    private let underlineBtn = CanvaToolbarButton(symbol: "underline", accessibility: "Underline")
    private let editBtn = CanvaToolbarButton(symbol: "keyboard", accessibility: "Edit text")
    private let duplicateBtn = CanvaToolbarButton(symbol: "plus.square.on.square", accessibility: "Duplicate")
    private let deleteBtn = CanvaToolbarButton(symbol: "trash", accessibility: "Delete")
    private var isBuilt = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func configure(host: MarkupViewController) {
        self.host = host
        guard !isBuilt else { return }
        isBuilt = true
        buildUI(host: host)
    }

    func updateAppearance(for traits: UITraitCollection) {
        let ink = MarkupEditorChromeUIKit.primaryText(traits)
        [fontChip, sizeChip, colorsChip, alignChip, spacingChip].forEach {
            var c = $0.configuration ?? .plain()
            c.baseForegroundColor = ink
            c.background.backgroundColor = MarkupEditorChromeUIKit.chipBackground(traits)
            $0.configuration = c
        }
        [boldBtn, italicBtn, underlineBtn, editBtn, duplicateBtn, deleteBtn].forEach { $0.applyTraits(traits) }
    }

    func refreshFor(_ box: MarkupTextBoxView?) {
        guard let box else {
            isUserInteractionEnabled = false
            alpha = 0.45
            return
        }
        isUserInteractionEnabled = true
        alpha = 1

        let font = UIFont(descriptor: box.elementStyle.fontDescriptor, size: 14)
        var fontConfig = fontChip.configuration ?? .plain()
        fontConfig.title = font.familyName
        fontChip.configuration = fontConfig

        var sizeConfig = sizeChip.configuration ?? .plain()
        sizeConfig.title = "\(Int(box.elementStyle.fontSize.rounded())) pt"
        sizeChip.configuration = sizeConfig

        boldBtn.isCanvaSelected = box.elementStyle.isBold
        italicBtn.isCanvaSelected = box.elementStyle.isItalic
        underlineBtn.isCanvaSelected = box.elementStyle.isUnderline
    }

    private func buildUI(host: MarkupViewController) {
        let traits = traitCollection

        func chip(_ button: UIButton, title: String, action: Selector) {
            var config = UIButton.Configuration.plain()
            config.title = title
            config.baseForegroundColor = MarkupEditorChromeUIKit.primaryText(traits)
            config.background.backgroundColor = MarkupEditorChromeUIKit.chipBackground(traits)
            config.background.cornerRadius = DS.Radius.chip
            config.background.strokeWidth = 1
            config.background.strokeColor = MarkupEditorChromeUIKit.divider(traits)
            config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var out = incoming
                out.font = DSUIKit.dockSectionFont
                return out
            }
            button.configuration = config
            button.addTarget(host, action: action, for: .touchUpInside)
            DSUIKit.installPressFeedback(on: button, scale: DS.Motion.pressScaleCompact)
        }

        chip(fontChip, title: "Font", action: #selector(MarkupViewController.pickCaptionFontFace))
        chip(sizeChip, title: "24 pt", action: #selector(MarkupViewController.openTextSizeSubsheet))
        chip(colorsChip, title: "Colors", action: #selector(MarkupViewController.openColorsSubsheet))
        chip(alignChip, title: "Align", action: #selector(MarkupViewController.openAlignmentSubsheet))
        chip(spacingChip, title: "Spacing", action: #selector(MarkupViewController.openSpacingSubsheet))

        boldBtn.addTarget(host, action: #selector(MarkupViewController.toggleBold), for: .touchUpInside)
        italicBtn.addTarget(host, action: #selector(MarkupViewController.toggleItalic), for: .touchUpInside)
        underlineBtn.addTarget(host, action: #selector(MarkupViewController.toggleMarkupUnderline), for: .touchUpInside)
        editBtn.addTarget(host, action: #selector(MarkupViewController.focusSelectedTextBox), for: .touchUpInside)
        duplicateBtn.addTarget(host, action: #selector(MarkupViewController.duplicateSelectedTextBox), for: .touchUpInside)
        deleteBtn.addTarget(host, action: #selector(MarkupViewController.deleteSelectedTextBox), for: .touchUpInside)
        [boldBtn, italicBtn, underlineBtn, editBtn, duplicateBtn, deleteBtn].forEach {
            $0.applyTraits(traits)
            DSUIKit.installPressFeedback(on: $0, scale: DS.Motion.pressScaleIcon)
        }

        let row = UIStackView(arrangedSubviews: [
            fontChip, sizeChip, colorsChip, alignChip, spacingChip,
            boldBtn, italicBtn, underlineBtn, editBtn, duplicateBtn, deleteBtn,
        ])
        row.axis = .horizontal
        row.spacing = 8
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false

        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(row)
        addSubview(scroll)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            row.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            row.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            row.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 52),
        ])
    }
}

// MARK: - Canva-style text element (style model + display/edit split)

enum MarkupTextBackgroundStyle: String, CaseIterable {
    case transparent = "Clear"
    case solid = "Color"
    case gradient = "Gradient"
    case glass = "Glass"
}

/// Single source of truth for how a text box looks — toolbar edits this, then we rebuild the string.
struct MarkupTextElementStyle {
    static let placeholder = "Double-tap to edit"

    var plainText: String = ""
    var fontSize: CGFloat = 24
    var isBold = true
    var isItalic = false
    var isUnderline = false
    var isStrikethrough = false
    var textColor: UIColor = .white
    /// Second stop for gradient text; independent from box fill colors.
    var textGradientEndColor: UIColor = UIColor(hexString: "#99DDC8") ?? .systemTeal
    var usesTextGradient = false
    var outlineColor: UIColor = .black
    var outlineWidth: CGFloat = 0
    var alignment: NSTextAlignment = .center
    var fontDescriptor: UIFontDescriptor = UIFont.systemFont(ofSize: 17, weight: .semibold).fontDescriptor

    func copy() -> MarkupTextElementStyle {
        self
    }

    var trimmedText: String {
        plainText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func coreAttributes(usePlaceholderStyle: Bool = false, gradientPatternSize: CGSize? = nil) -> [NSAttributedString.Key: Any] {
        var fontTraits: UIFontDescriptor.SymbolicTraits = []
        if isBold { fontTraits.insert(.traitBold) }
        if isItalic { fontTraits.insert(.traitItalic) }
        let desc = fontDescriptor.withSymbolicTraits(fontTraits) ?? fontDescriptor
        let font = UIFont(descriptor: desc, size: fontSize)
        let p = NSMutableParagraphStyle()
        p.alignment = alignment
        let fg: UIColor
        if usePlaceholderStyle {
            fg = textColor.withAlphaComponent(0.55)
        } else if usesTextGradient, let sz = gradientPatternSize, sz.width > 2 {
            fg = markupGradientPatternColor(size: sz, start: textColor, end: textGradientEndColor)
        } else {
            fg = textColor
        }
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: fg,
            .paragraphStyle: p,
        ]
        if isUnderline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if isStrikethrough { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if outlineWidth > 0.25 {
            attrs[.strokeColor] = outlineColor
            attrs[.strokeWidth] = -outlineWidth * 2
        }
        return attrs
    }

    func typingAttributes() -> [NSAttributedString.Key: Any] {
        coreAttributes(usePlaceholderStyle: false)
    }

    func attributedString(showPlaceholder: Bool, gradientPatternSize: CGSize? = nil) -> NSAttributedString {
        let empty = trimmedText.isEmpty
        let usePlaceholder = showPlaceholder && empty
        let string = usePlaceholder ? Self.placeholder : plainText
        return NSAttributedString(
            string: string,
            attributes: coreAttributes(usePlaceholderStyle: usePlaceholder, gradientPatternSize: gradientPatternSize)
        )
    }
}

final class MarkupTextBoxView: UIView, UITextViewDelegate {
    private enum ResizeCorner: Int {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    static let minWidth: CGFloat = 80
    private static let handleSize: CGFloat = 22
    /// iOS points (pt) — same unit as font size; ~12–16 pt is typical for caption labels.
    static let defaultContentPadding = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
    static let defaultMarginHorizontal: CGFloat = 8

    static func minimumHeight(for fontSize: CGFloat, padding: UIEdgeInsets = defaultContentPadding) -> CGFloat {
        let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        return ceil(font.lineHeight) + padding.top + padding.bottom
    }

    let displayLabel = UILabel()
    let textView = UITextView()
    private let plateView = UIView()
    private var plateGradientLayer: CAGradientLayer?
    private var blurView: UIVisualEffectView?
    private let selectionRing = UIView()
    private var resizeHandles: [ResizeCorner: UIView] = [:]

    var boxID = UUID()
    var elementStyle = MarkupTextElementStyle()
    var contentPadding = MarkupTextBoxView.defaultContentPadding
    var marginHorizontal = MarkupTextBoxView.defaultMarginHorizontal
    var isEditingText = false
    private var resizeStartSize: CGSize = .zero
    private var resizeStartFontSize: CGFloat = 24
    private var pinchStartFontSize: CGFloat = 24
    private var plateLeading: NSLayoutConstraint!
    private var plateTrailing: NSLayoutConstraint!
    private var labelTop: NSLayoutConstraint!
    private var labelLeading: NSLayoutConstraint!
    private var labelTrailing: NSLayoutConstraint!
    private var labelBottom: NSLayoutConstraint!
    private var textViewTop: NSLayoutConstraint!
    private var textViewLeading: NSLayoutConstraint!
    private var textViewTrailing: NSLayoutConstraint!
    private var textViewBottom: NSLayoutConstraint!

    var baseFontSize: CGFloat {
        get { elementStyle.fontSize }
        set { elementStyle.fontSize = newValue }
    }

    var backgroundStyle: MarkupTextBackgroundStyle = .solid {
        didSet { applyBackgroundStyle() }
    }
    /// Box fill — never synced with `elementStyle.textColor`.
    var fillColor: UIColor = UIColor(white: 0.05, alpha: 0.88)
    var fillSecondaryColor: UIColor = UIColor(white: 0.22, alpha: 0.88)
    var fillOpacity: CGFloat = 1.0

    weak var markupHost: MarkupViewController?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = true
        clipsToBounds = false

        plateView.translatesAutoresizingMaskIntoConstraints = false
        plateView.layer.cornerRadius = 12
        plateView.layer.cornerCurve = .continuous
        plateView.isUserInteractionEnabled = false
        addSubview(plateView)

        displayLabel.translatesAutoresizingMaskIntoConstraints = false
        displayLabel.numberOfLines = 0
        displayLabel.backgroundColor = .clear
        displayLabel.isUserInteractionEnabled = false
        addSubview(displayLabel)

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = .clear
        textView.textContainerInset = contentPadding
        textView.textContainer.lineFragmentPadding = 0
        textView.delegate = self
        textView.isScrollEnabled = false
        textView.keyboardDismissMode = .interactive
        textView.allowsEditingTextAttributes = false
        textView.isHidden = true
        textView.isUserInteractionEnabled = false
        addSubview(textView)

        selectionRing.translatesAutoresizingMaskIntoConstraints = false
        selectionRing.layer.cornerRadius = 14
        selectionRing.layer.cornerCurve = .continuous
        selectionRing.layer.borderWidth = 2
        selectionRing.layer.borderColor = AppTheme.accentUIColor.cgColor
        selectionRing.isUserInteractionEnabled = false
        selectionRing.isHidden = true
        addSubview(selectionRing)

        plateLeading = plateView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: marginHorizontal)
        plateTrailing = plateView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -marginHorizontal)
        labelTop = displayLabel.topAnchor.constraint(equalTo: plateView.topAnchor, constant: contentPadding.top)
        labelLeading = displayLabel.leadingAnchor.constraint(equalTo: plateView.leadingAnchor, constant: contentPadding.left)
        labelTrailing = displayLabel.trailingAnchor.constraint(equalTo: plateView.trailingAnchor, constant: -contentPadding.right)
        labelBottom = displayLabel.bottomAnchor.constraint(equalTo: plateView.bottomAnchor, constant: -contentPadding.bottom)
        textViewTop = textView.topAnchor.constraint(equalTo: plateView.topAnchor, constant: contentPadding.top)
        textViewLeading = textView.leadingAnchor.constraint(equalTo: plateView.leadingAnchor, constant: contentPadding.left)
        textViewTrailing = textView.trailingAnchor.constraint(equalTo: plateView.trailingAnchor, constant: -contentPadding.right)
        textViewBottom = textView.bottomAnchor.constraint(equalTo: plateView.bottomAnchor, constant: -contentPadding.bottom)

        NSLayoutConstraint.activate([
            plateView.topAnchor.constraint(equalTo: topAnchor),
            plateLeading,
            plateTrailing,
            plateView.bottomAnchor.constraint(equalTo: bottomAnchor),
            labelTop, labelLeading, labelTrailing, labelBottom,
            textViewTop, textViewLeading, textViewTrailing, textViewBottom,
            selectionRing.topAnchor.constraint(equalTo: topAnchor, constant: -3),
            selectionRing.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -3),
            selectionRing.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 3),
            selectionRing.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 3),
        ])
        applyContentInsetsToViews()

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.delegate = self
        addGestureRecognizer(tap)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        tap.require(toFail: doubleTap)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.45
        addGestureRecognizer(longPress)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        addGestureRecognizer(pinch)

        installResizeHandles()
        applyBackgroundStyle()
        refreshFromStyle()
    }

    private func installResizeHandles() {
        for corner in [ResizeCorner.topLeft, .topRight, .bottomLeft, .bottomRight] {
            let handle = UIView(frame: CGRect(x: 0, y: 0, width: Self.handleSize, height: Self.handleSize))
            handle.backgroundColor = AppTheme.accentUIColor
            handle.layer.cornerRadius = Self.handleSize / 2
            handle.layer.borderWidth = 2
            handle.layer.borderColor = UIColor.white.cgColor
            handle.isHidden = true
            handle.tag = corner.rawValue
            handle.isUserInteractionEnabled = true
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handleResizePan(_:)))
            pan.delegate = self
            handle.addGestureRecognizer(pan)
            addSubview(handle)
            resizeHandles[corner] = handle
        }
    }

    private func layoutResizeHandles() {
        let s = Self.handleSize
        let w = bounds.width
        let h = bounds.height
        resizeHandles[.topLeft]?.center = CGPoint(x: 0, y: 0)
        resizeHandles[.topRight]?.center = CGPoint(x: w, y: 0)
        resizeHandles[.bottomLeft]?.center = CGPoint(x: 0, y: h)
        resizeHandles[.bottomRight]?.center = CGPoint(x: w, y: h)
        resizeHandles.values.forEach { $0.bounds = CGRect(x: 0, y: 0, width: s, height: s) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func applyContentInsetsToViews() {
        plateLeading.constant = marginHorizontal
        plateTrailing.constant = -marginHorizontal
        labelTop.constant = contentPadding.top
        labelLeading.constant = contentPadding.left
        labelTrailing.constant = -contentPadding.right
        labelBottom.constant = -contentPadding.bottom
        textViewTop.constant = contentPadding.top
        textViewLeading.constant = contentPadding.left
        textViewTrailing.constant = -contentPadding.right
        textViewBottom.constant = -contentPadding.bottom
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
    }

    func copyState(from source: MarkupTextBoxView) {
        elementStyle = source.elementStyle.copy()
        contentPadding = source.contentPadding
        marginHorizontal = source.marginHorizontal
        backgroundStyle = source.backgroundStyle
        fillColor = source.fillColor
        fillSecondaryColor = source.fillSecondaryColor
        fillOpacity = source.fillOpacity
        applyContentInsetsToViews()
        applyBackgroundStyle()
        refreshFromStyle()
    }

    func refreshFromStyle() {
        layoutIfNeeded()
        let patternSize = CGSize(width: max(40, plateView.bounds.width), height: max(20, plateView.bounds.height))
        let attr = elementStyle.attributedString(showPlaceholder: !isEditingText, gradientPatternSize: patternSize)
        displayLabel.attributedText = attr
        if isEditingText {
            applyStyleToEditorPreservingSelection()
        }
    }

    func applyStyleToEditorPreservingSelection() {
        guard isEditingText else { return }
        let selected = textView.selectedRange
        let plain = textView.text ?? ""
        elementStyle.plainText = plain
        // Solid color while typing — gradient pattern on UITextView tiles incorrectly.
        let attrs = elementStyle.coreAttributes(usePlaceholderStyle: false)
        textView.attributedText = NSAttributedString(string: plain, attributes: attrs)
        textView.typingAttributes = attrs
        textView.textAlignment = elementStyle.alignment
        textView.textColor = elementStyle.textColor
        let length = (textView.text as NSString).length
        let loc = min(selected.location, length)
        let len = min(selected.length, max(0, length - loc))
        textView.selectedRange = NSRange(location: loc, length: len)
    }

    func pullPlainTextFromEditor() {
        elementStyle.plainText = textView.text ?? ""
    }

    func beginEditing() {
        guard !isEditingText else { return }
        isEditingText = true
        textView.isHidden = false
        textView.isUserInteractionEnabled = true
        textView.isScrollEnabled = true
        displayLabel.isHidden = true
        markupHost?.installTypingAccessory(on: textView)
        applyStyleToEditorPreservingSelection()
        textView.becomeFirstResponder()
        setSelected(true)
    }

    func endEditingText() {
        guard isEditingText else { return }
        pullPlainTextFromEditor()
        isEditingText = false
        textView.resignFirstResponder()
        textView.isHidden = true
        textView.isUserInteractionEnabled = false
        displayLabel.isHidden = false
        refreshFromStyle()
    }

    func setSelected(_ selected: Bool) {
        selectionRing.isHidden = !selected
        let showChrome = selected && !isEditingText
        resizeHandles.values.forEach { $0.isHidden = !showChrome }
        if selected { layoutResizeHandles() }
    }

    var hasText: Bool {
        !elementStyle.trimmedText.isEmpty
    }

    var exportAttributedText: NSAttributedString {
        let sz = CGSize(width: max(40, plateView.bounds.width), height: max(20, plateView.bounds.height))
        return elementStyle.attributedString(showPlaceholder: false, gradientPatternSize: sz)
    }

    func applyBackgroundStyle() {
        blurView?.removeFromSuperview()
        blurView = nil
        plateGradientLayer?.removeFromSuperlayer()
        plateGradientLayer = nil
        plateView.backgroundColor = .clear
        plateView.layer.borderWidth = 0

        switch backgroundStyle {
        case .transparent:
            plateView.backgroundColor = .clear
            plateView.layer.borderWidth = 1
            plateView.layer.borderColor = UIColor.white.withAlphaComponent(0.35).cgColor
        case .solid:
            plateView.backgroundColor = fillColor.withAlphaComponent(fillOpacity)
            plateView.layer.borderWidth = 1
            plateView.layer.borderColor = UIColor.white.withAlphaComponent(0.42).cgColor
        case .gradient:
            plateView.layer.borderWidth = 1
            plateView.layer.borderColor = UIColor.white.withAlphaComponent(0.35).cgColor
            let g = CAGradientLayer()
            g.cornerRadius = plateView.layer.cornerRadius
            g.colors = [
                fillColor.withAlphaComponent(fillOpacity).cgColor,
                fillSecondaryColor.withAlphaComponent(fillOpacity * 0.85).cgColor,
            ]
            g.startPoint = CGPoint(x: 0, y: 0)
            g.endPoint = CGPoint(x: 1, y: 1)
            plateGradientLayer = g
            plateView.layer.insertSublayer(g, at: 0)
            syncPlateGradientFrame()
        case .glass:
            let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
            blur.translatesAutoresizingMaskIntoConstraints = false
            blur.isUserInteractionEnabled = false
            blur.layer.cornerRadius = 12
            blur.layer.cornerCurve = .continuous
            blur.clipsToBounds = true
            blur.alpha = fillOpacity
            plateView.addSubview(blur)
            NSLayoutConstraint.activate([
                blur.topAnchor.constraint(equalTo: plateView.topAnchor),
                blur.leadingAnchor.constraint(equalTo: plateView.leadingAnchor),
                blur.trailingAnchor.constraint(equalTo: plateView.trailingAnchor),
                blur.bottomAnchor.constraint(equalTo: plateView.bottomAnchor),
            ])
            blurView = blur
            plateView.layer.borderWidth = 1
            plateView.layer.borderColor = UIColor.white.withAlphaComponent(0.28).cgColor
        }
    }

    private func syncPlateGradientFrame() {
        guard let g = plateGradientLayer else { return }
        g.frame = plateView.bounds
        g.cornerRadius = plateView.layer.cornerRadius
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        syncPlateGradientFrame()
        layoutResizeHandles()
    }

    func resizeToFitText(maxWidth: CGFloat, maxHeight: CGFloat) {
        let insetW = contentPadding.left + contentPadding.right + marginHorizontal * 2
        let insetH = contentPadding.top + contentPadding.bottom
        let minH = Self.minimumHeight(for: elementStyle.fontSize, padding: contentPadding)
        let contentWidth = max(40, maxWidth - insetW)
        displayLabel.preferredMaxLayoutWidth = contentWidth
        let target = CGSize(width: contentWidth, height: .greatestFiniteMagnitude)
        let fitted = displayLabel.sizeThatFits(target)
        var f = frame
        f.size.width = min(maxWidth, max(Self.minWidth, fitted.width + insetW))
        let contentH = max(minH, fitted.height + insetH)
        f.size.height = min(maxHeight, contentH)
        frame = f
        layoutIfNeeded()
        if isEditingText {
            textView.isScrollEnabled = f.height >= maxHeight - 1
        }
    }

    @objc private func handleLongPress(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        markupHost?.showTextBoxActionMenu(for: self, sourceView: self)
    }

    @objc private func handleTap() {
        markupHost?.selectTextBox(self, beginEditing: false)
    }

    @objc private func handleDoubleTap() {
        markupHost?.selectTextBox(self, beginEditing: true)
    }

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        guard !isEditingText, let host = markupHost, host.isTextBoxSelected(self) else { return }
        if g.state == .began { host.selectTextBox(self, beginEditing: false) }
        let t = g.translation(in: superview)
        center = CGPoint(x: center.x + t.x, y: center.y + t.y)
        g.setTranslation(.zero, in: superview)
        host.constrainTextBox(self)
    }

    @objc private func handleResizePan(_ g: UIPanGestureRecognizer) {
        guard !isEditingText,
              let host = markupHost,
              let handle = g.view,
              let corner = ResizeCorner(rawValue: handle.tag) else { return }
        if g.state == .began {
            host.selectTextBox(self, beginEditing: false)
            resizeStartSize = frame.size
            resizeStartFontSize = elementStyle.fontSize
        }
        let t = g.translation(in: superview)
        var f = frame
        let minW = Self.minWidth
        let minH = Self.minimumHeight(for: elementStyle.fontSize, padding: contentPadding)
        switch corner {
        case .bottomRight:
            f.size.width = max(minW, f.width + t.x)
            f.size.height = max(minH, f.height + t.y)
        case .bottomLeft:
            f.origin.x += t.x
            f.size.width = max(minW, f.width - t.x)
            f.size.height = max(minH, f.height + t.y)
        case .topRight:
            f.origin.y += t.y
            f.size.width = max(minW, f.width + t.x)
            f.size.height = max(minH, f.height - t.y)
        case .topLeft:
            f.origin.x += t.x
            f.origin.y += t.y
            f.size.width = max(minW, f.width - t.x)
            f.size.height = max(minH, f.height - t.y)
        }
        frame = f
        g.setTranslation(.zero, in: superview)
        let scale = max(0.35, min(3.2, f.width / max(1, resizeStartSize.width)))
        elementStyle.fontSize = max(12, min(72, resizeStartFontSize * scale))
        refreshFromStyle()
        host.constrainTextBox(self)
        if g.state == .ended || g.state == .cancelled {
            host.resizeTextBox(self)
        }
    }

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        guard !isEditingText, markupHost?.isTextBoxSelected(self) == true else { return }
        if g.state == .began { pinchStartFontSize = elementStyle.fontSize }
        if g.state == .changed {
            let factor = CGFloat(min(2.5, max(0.4, g.scale)))
            elementStyle.fontSize = max(12, min(72, pinchStartFontSize * factor))
            refreshFromStyle()
            markupHost?.resizeTextBox(self)
            markupHost?.constrainTextBox(self)
        }
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        isEditingText = true
        markupHost?.textBoxDidBeginEditing(self)
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        endEditingText()
        markupHost?.textBoxDidEndEditing(self)
    }

    func textViewDidChange(_ textView: UITextView) {
        elementStyle.plainText = textView.text ?? ""
        applyStyleToEditorPreservingSelection()
        markupHost?.resizeTextBox(self)
        applyBackgroundStyle()
        markupHost?.ensureActiveTextBoxVisible(animated: false)
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if isEditingText, gestureRecognizer is UIPanGestureRecognizer || gestureRecognizer is UIPinchGestureRecognizer {
            return false
        }
        if gestureRecognizer is UIPanGestureRecognizer || gestureRecognizer is UIPinchGestureRecognizer {
            return markupHost?.isTextBoxSelected(self) == true
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }
}

extension MarkupTextBoxView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        gestureRecognizer is UIPanGestureRecognizer || gestureRecognizer is UIPinchGestureRecognizer
    }
}

// MARK: - Markup view controller

final class MarkupViewController: UIViewController, UIColorPickerViewControllerDelegate, UIFontPickerViewControllerDelegate {
    var coordinator: MarkupEditorBridge.Coordinator!
    var baseImage: UIImage!

    fileprivate let imageView = UIImageView()
    fileprivate let canvas = PKCanvasView()
    private let overlayHost = MarkupPassthroughOverlay()
    fileprivate(set) var toolPicker: PKToolPicker?
    private var textBoxes: [MarkupTextBoxView] = []
    private weak var selectedTextBox: MarkupTextBoxView?
    private enum MarkupInteractionMode {
        case idle
        case draw
        case text
    }

    private var interactionMode: MarkupInteractionMode = .idle
    private weak var textModeButton: UIButton?
    private weak var drawModeButton: UIButton?
    private weak var panelTitleLabel: UILabel?
    private weak var panelDoneButton: UIButton?
    private var colorPickTarget: MarkupColorPickTarget = .text
    private let bottomDock = UIView()
    private let bottomToolBar = UIStackView()
    private var bottomDockHeight: NSLayoutConstraint!
    private var bottomDockBottomConstraint: NSLayoutConstraint!
    private let textCustomizePanel = UIView()
    private let textCustomizeScroll = UIScrollView()
    private let subsheetHost = UIView()
    private var isTextSubsheetOpen = false
    private lazy var canvaTextToolbar = MarkupCanvaTextToolbar()
    private var imageBottomToToolbar: NSLayoutConstraint!
    private var imageBottomToCustomize: NSLayoutConstraint!
    private var customizePanelHeight: NSLayoutConstraint!
    private var keyboardOverlap: CGFloat = 0
    private var isEditingText = false
    private var isTextCustomizePanelVisible = false

    var currentMaxTextWidth: CGFloat { imageRectInOverlay().width - 16 }
    var currentMaxTextHeight: CGFloat { imageRectInOverlay().height * 0.88 }

    private let bottomToolbarHeight: CGFloat = 52
    private let textCustomizeCompactHeight: CGFloat = 108
    private let textCustomizeSubsheetHeight: CGFloat = 316
    /// Lifts the Text / Draw dock above the floating PencilKit tool palette.
    private let pencilToolbarClearance: CGFloat = 88
    private var dockSheetSurface: DSOperationalSheetSurfaceView?
    private var textPanelSheetSurface: DSOperationalSheetSurfaceView?
    private weak var panelHeaderDivider: UIView?

    override func viewDidLoad() {
        super.viewDidLoad()
        applyMarkupChrome()
        imageView.image = baseImage
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: .label, width: 4)
        let canvasTap = UITapGestureRecognizer(target: self, action: #selector(canvasBackgroundTapped(_:)))
        canvasTap.cancelsTouchesInView = false
        canvasTap.delegate = self
        canvas.addGestureRecognizer(canvasTap)
        overlayHost.translatesAutoresizingMaskIntoConstraints = false
        overlayHost.backgroundColor = .clear

        navigationItem.title = "Markup"
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))

        let flipBtn = UIBarButtonItem(image: UIImage(systemName: "arrow.left.and.right"), style: .plain, target: self, action: #selector(flipImageTapped))
        let more = UIMenu(title: "", children: [
            UIAction(title: "Undo", image: UIImage(systemName: "arrow.uturn.backward")) { [weak self] _ in self?.canvas.undoManager?.undo() },
            UIAction(title: "Redo", image: UIImage(systemName: "arrow.uturn.forward")) { [weak self] _ in self?.canvas.undoManager?.redo() },
            UIAction(title: "Clear drawing", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in self?.canvas.drawing = PKDrawing() },
            UIAction(title: "Delete selected text", image: UIImage(systemName: "text.badge.minus"), attributes: .destructive) { [weak self] _ in self?.deleteSelectedTextBox() },
        ])
        let moreBtn = UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"), menu: more)
        let textBtn = UIBarButtonItem(title: "Text", style: .plain, target: self, action: #selector(addTextBoxTapped))
        let doneBtn = UIBarButtonItem(image: UIImage(systemName: "checkmark.circle.fill"), style: .done, target: self, action: #selector(saveTapped))
        navigationItem.rightBarButtonItems = [doneBtn, textBtn, moreBtn, flipBtn]

        setupBottomChrome()
        canvaTextToolbar.configure(host: self)
        canvaTextToolbar.updateAppearance(for: traitCollection)
        registerKeyboardObservers()
        updateModeButtonChrome()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: MarkupViewController, _) in
            self.applyMarkupChrome()
        }
    }

    private func applyMarkupChrome() {
        let traits = traitCollection
        view.backgroundColor = MarkupEditorChromeUIKit.pageBackground(traits)
        bottomDock.backgroundColor = MarkupEditorChromeUIKit.dockBackground(traits)
        textCustomizePanel.backgroundColor = MarkupEditorChromeUIKit.panelBackground(traits)
        panelTitleLabel?.textColor = MarkupEditorChromeUIKit.primaryText(traits)
        panelDoneButton?.setTitleColor(MarkupEditorChromeUIKit.headerActionText(traits), for: .normal)
        canvaTextToolbar.updateAppearance(for: traits)
        updateModeButtonChrome()
    }

    private func updateModeButtonChrome() {
        let traits = traitCollection
        let ink = MarkupEditorChromeUIKit.primaryText(traits)
        let chip = MarkupEditorChromeUIKit.chipBackground(traits)
        let selected = MarkupEditorChromeUIKit.chipSelected(traits)
        let border = MarkupEditorChromeUIKit.divider(traits)
        let accentBorder = MarkupEditorChromeUIKit.accent(traits)
        for (btn, active) in [(textModeButton, interactionMode == .text), (drawModeButton, interactionMode == .draw)] {
            guard var config = btn?.configuration else { continue }
            config.baseForegroundColor = ink
            config.background.backgroundColor = active ? selected : chip
            config.background.cornerRadius = DS.Radius.chip
            config.background.strokeWidth = active ? 1.5 : 1
            config.background.strokeColor = active ? accentBorder : border
            btn?.configuration = config
        }
    }

    private func syncDrawingToolsVisibility() {
        let showPencil = interactionMode == .draw && !isTextCustomizePanelVisible && !isEditingText
        setDrawingToolsVisible(showPencil)
        canvas.isUserInteractionEnabled = interactionMode == .draw && !isTextCustomizePanelVisible
        updatePencilDockInset(showPencil: showPencil)
        if showPencil {
            view.bringSubviewToFront(textCustomizePanel)
            view.bringSubviewToFront(bottomDock)
        }
    }

    private func updatePencilDockInset(showPencil: Bool) {
        bottomDockBottomConstraint?.constant = showPencil ? -pencilToolbarClearance : 0
        bottomDock.layer.zPosition = showPencil ? 100 : 20
        DSUIKit.animateOperationalSheet { self.view.layoutIfNeeded() }
    }

    private func elevateMarkupChrome() {
        view.bringSubviewToFront(textCustomizePanel)
        view.bringSubviewToFront(bottomDock)
    }

    func installTypingAccessory(on textView: UITextView) {
        let bar = UIToolbar()
        bar.barStyle = traitCollection.userInterfaceStyle == .dark ? .black : .default
        bar.isTranslucent = true
        bar.sizeToFit()
        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let done = UIBarButtonItem(
            title: "Done",
            style: .done,
            target: self,
            action: #selector(finishTypingTapped)
        )
        done.tintColor = MarkupEditorChromeUIKit.headerActionText(traitCollection)
        bar.items = [flex, done]
        textView.inputAccessoryView = bar
    }

    @objc func finishTypingTapped() {
        commitActiveTextEditing()
    }

    @objc func panelHeaderTapped() {
        if isTextSubsheetOpen {
            closeTextSubsheet()
            return
        }
        commitActiveTextEditing()
    }

    private func commitActiveTextEditing() {
        view.endEditing(true)
        for box in textBoxes where box.isEditingText || box.textView.isFirstResponder {
            box.pullPlainTextFromEditor()
            box.isEditingText = false
            box.textView.resignFirstResponder()
            box.textView.isHidden = true
            box.textView.isUserInteractionEnabled = false
            box.displayLabel.isHidden = false
            box.refreshFromStyle()
            box.applyBackgroundStyle()
            resizeTextBox(box)
        }
        isEditingText = false
        syncDrawingToolsVisibility()
        if let box = selectedTextBox ?? activeBox() {
            box.setSelected(true)
            canvaTextToolbar.refreshFor(box)
        }
    }

    @objc func enterTextMode() {
        interactionMode = .text
        updateModeButtonChrome()
        syncDrawingToolsVisibility()
        if textBoxes.isEmpty {
            addTextBox(focus: true)
        } else if let box = selectedTextBox ?? textBoxes.last {
            selectTextBox(box, beginEditing: false)
        } else {
            setTextCustomizePanelVisible(true)
        }
    }

    private func setupBottomChrome() {
        bottomToolBar.axis = .horizontal
        bottomToolBar.spacing = DS.Space.stack
        bottomToolBar.distribution = .fillEqually
        bottomToolBar.translatesAutoresizingMaskIntoConstraints = false
        bottomDock.translatesAutoresizingMaskIntoConstraints = false
        bottomDock.backgroundColor = .clear

        let dockSurface = DSOperationalSheetSurfaceView()
        dockSurface.translatesAutoresizingMaskIntoConstraints = false
        dockSheetSurface = dockSurface
        bottomDock.insertSubview(dockSurface, at: 0)
        NSLayoutConstraint.activate([
            dockSurface.topAnchor.constraint(equalTo: bottomDock.topAnchor),
            dockSurface.leadingAnchor.constraint(equalTo: bottomDock.leadingAnchor),
            dockSurface.trailingAnchor.constraint(equalTo: bottomDock.trailingAnchor),
            dockSurface.bottomAnchor.constraint(equalTo: bottomDock.bottomAnchor),
        ])

        bottomToolBar.backgroundColor = .clear
        bottomToolBar.isLayoutMarginsRelativeArrangement = true
        bottomToolBar.layoutMargins = UIEdgeInsets(
            top: DS.Space.stack,
            left: DSUIKit.contentHorizontalPadding,
            bottom: DS.Space.stack,
            right: DSUIKit.contentHorizontalPadding
        )

        func modeButton(title: String, symbol: String, action: Selector) -> UIButton {
            var config = UIButton.Configuration.plain()
            config.title = title
            config.image = UIImage(systemName: symbol)
            config.imagePadding = 6
            config.baseForegroundColor = MarkupEditorChromeUIKit.primaryText(traitCollection)
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var out = incoming
                out.font = DSUIKit.dockSectionFont
                return out
            }
            config.background.cornerRadius = DS.Radius.chip
            config.background.strokeWidth = 1
            config.background.strokeColor = MarkupEditorChromeUIKit.divider(traitCollection)
            config.background.backgroundColor = MarkupEditorChromeUIKit.chipBackground(traitCollection)
            config.contentInsets = NSDirectionalEdgeInsets(top: 9, leading: 10, bottom: 9, trailing: 10)
            let b = UIButton(configuration: config)
            b.addTarget(self, action: action, for: .touchUpInside)
            DSUIKit.installPressFeedback(on: b, scale: DS.Motion.pressScaleCompact)
            return b
        }

        let textModeBtn = modeButton(title: "Text", symbol: "textformat", action: #selector(enterTextMode))
        let drawModeBtn = modeButton(title: "Draw", symbol: "pencil.tip", action: #selector(enterDrawMode))
        textModeButton = textModeBtn
        drawModeButton = drawModeBtn
        bottomToolBar.addArrangedSubview(textModeBtn)
        bottomToolBar.addArrangedSubview(drawModeBtn)

        textCustomizePanel.translatesAutoresizingMaskIntoConstraints = false
        textCustomizePanel.backgroundColor = .clear
        textCustomizePanel.clipsToBounds = true
        textCustomizePanel.isHidden = true

        let panelSurface = DSOperationalSheetSurfaceView()
        panelSurface.translatesAutoresizingMaskIntoConstraints = false
        textPanelSheetSurface = panelSurface
        textCustomizePanel.addSubview(panelSurface)
        NSLayoutConstraint.activate([
            panelSurface.topAnchor.constraint(equalTo: textCustomizePanel.topAnchor),
            panelSurface.leadingAnchor.constraint(equalTo: textCustomizePanel.leadingAnchor),
            panelSurface.trailingAnchor.constraint(equalTo: textCustomizePanel.trailingAnchor),
            panelSurface.bottomAnchor.constraint(equalTo: textCustomizePanel.bottomAnchor),
        ])

        let panelTitle = UILabel()
        panelTitle.text = "Text"
        panelTitle.font = DSUIKit.sectionTitleFont
        panelTitle.textColor = MarkupEditorChromeUIKit.primaryText(traitCollection)
        panelTitle.translatesAutoresizingMaskIntoConstraints = false
        panelTitleLabel = panelTitle

        let panelDone = UIButton(type: .system)
        panelDone.setTitle("Close", for: .normal)
        panelDone.titleLabel?.font = DSUIKit.bodyEmphasisFont
        panelDone.setTitleColor(MarkupEditorChromeUIKit.headerActionText(traitCollection), for: .normal)
        panelDone.translatesAutoresizingMaskIntoConstraints = false
        panelDone.addTarget(self, action: #selector(panelHeaderTapped), for: .touchUpInside)
        panelDoneButton = panelDone

        let headerDivider = UIView()
        headerDivider.backgroundColor = MarkupEditorChromeUIKit.divider(traitCollection)
        headerDivider.translatesAutoresizingMaskIntoConstraints = false
        panelHeaderDivider = headerDivider

        textCustomizeScroll.translatesAutoresizingMaskIntoConstraints = false
        textCustomizeScroll.alwaysBounceVertical = false
        textCustomizeScroll.showsVerticalScrollIndicator = false
        subsheetHost.translatesAutoresizingMaskIntoConstraints = false
        subsheetHost.isHidden = true
        canvaTextToolbar.translatesAutoresizingMaskIntoConstraints = false

        textCustomizePanel.addSubview(panelTitle)
        textCustomizePanel.addSubview(panelDone)
        textCustomizePanel.addSubview(headerDivider)
        textCustomizePanel.addSubview(textCustomizeScroll)
        textCustomizePanel.addSubview(subsheetHost)
        textCustomizeScroll.addSubview(canvaTextToolbar)

        view.addSubview(imageView)
        view.addSubview(canvas)
        view.addSubview(overlayHost)
        view.addSubview(textCustomizePanel)
        view.addSubview(bottomDock)
        bottomDock.addSubview(bottomToolBar)
        bottomDock.layer.zPosition = 20
        textCustomizePanel.layer.zPosition = 19

        bottomDockHeight = bottomDock.heightAnchor.constraint(equalToConstant: bottomToolbarHeight)
        customizePanelHeight = textCustomizePanel.heightAnchor.constraint(equalToConstant: 0)
        imageBottomToToolbar = imageView.bottomAnchor.constraint(equalTo: bottomDock.topAnchor, constant: -4)
        imageBottomToCustomize = imageView.bottomAnchor.constraint(equalTo: textCustomizePanel.topAnchor, constant: -4)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            imageBottomToToolbar,
            canvas.topAnchor.constraint(equalTo: imageView.topAnchor),
            canvas.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: imageView.bottomAnchor),
            overlayHost.topAnchor.constraint(equalTo: imageView.topAnchor),
            overlayHost.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            overlayHost.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
            overlayHost.bottomAnchor.constraint(equalTo: imageView.bottomAnchor),
            textCustomizePanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textCustomizePanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textCustomizePanel.bottomAnchor.constraint(equalTo: bottomDock.topAnchor),
            customizePanelHeight,
            bottomDock.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomDock.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomDockHeight,
            bottomToolBar.topAnchor.constraint(equalTo: bottomDock.topAnchor),
            bottomToolBar.leadingAnchor.constraint(equalTo: bottomDock.leadingAnchor),
            bottomToolBar.trailingAnchor.constraint(equalTo: bottomDock.trailingAnchor),
            bottomToolBar.bottomAnchor.constraint(equalTo: bottomDock.safeAreaLayoutGuide.bottomAnchor),
            panelTitle.topAnchor.constraint(equalTo: textCustomizePanel.topAnchor, constant: DSUIKit.headerVerticalPadding),
            panelTitle.leadingAnchor.constraint(equalTo: textCustomizePanel.leadingAnchor, constant: DSUIKit.headerHorizontalPadding),
            panelDone.centerYAnchor.constraint(equalTo: panelTitle.centerYAnchor),
            panelDone.trailingAnchor.constraint(equalTo: textCustomizePanel.trailingAnchor, constant: -DSUIKit.headerHorizontalPadding),
            headerDivider.topAnchor.constraint(equalTo: panelTitle.bottomAnchor, constant: DSUIKit.headerVerticalPadding),
            headerDivider.leadingAnchor.constraint(equalTo: textCustomizePanel.leadingAnchor),
            headerDivider.trailingAnchor.constraint(equalTo: textCustomizePanel.trailingAnchor),
            headerDivider.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),
            textCustomizeScroll.topAnchor.constraint(equalTo: headerDivider.bottomAnchor, constant: DS.Space.stack),
            textCustomizeScroll.leadingAnchor.constraint(equalTo: textCustomizePanel.leadingAnchor),
            textCustomizeScroll.trailingAnchor.constraint(equalTo: textCustomizePanel.trailingAnchor),
            textCustomizeScroll.heightAnchor.constraint(equalToConstant: 44),
            subsheetHost.topAnchor.constraint(equalTo: textCustomizeScroll.bottomAnchor, constant: DS.Space.tight),
            subsheetHost.leadingAnchor.constraint(equalTo: textCustomizePanel.leadingAnchor, constant: DSUIKit.contentHorizontalPadding),
            subsheetHost.trailingAnchor.constraint(equalTo: textCustomizePanel.trailingAnchor, constant: -DSUIKit.contentHorizontalPadding),
            subsheetHost.bottomAnchor.constraint(equalTo: textCustomizePanel.bottomAnchor, constant: -DS.Space.stack),
            canvaTextToolbar.topAnchor.constraint(equalTo: textCustomizeScroll.contentLayoutGuide.topAnchor),
            canvaTextToolbar.leadingAnchor.constraint(equalTo: textCustomizeScroll.frameLayoutGuide.leadingAnchor, constant: DSUIKit.contentHorizontalPadding),
            canvaTextToolbar.trailingAnchor.constraint(equalTo: textCustomizeScroll.frameLayoutGuide.trailingAnchor, constant: -DSUIKit.contentHorizontalPadding),
            canvaTextToolbar.bottomAnchor.constraint(equalTo: textCustomizeScroll.contentLayoutGuide.bottomAnchor),
            canvaTextToolbar.heightAnchor.constraint(equalTo: textCustomizeScroll.frameLayoutGuide.heightAnchor),
            canvaTextToolbar.widthAnchor.constraint(equalTo: textCustomizeScroll.frameLayoutGuide.widthAnchor, constant: -(DSUIKit.contentHorizontalPadding * 2)),
        ])
        bottomDockBottomConstraint = bottomDock.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        bottomDockBottomConstraint.isActive = true
        updateBottomDockHeight()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateBottomDockHeight()
    }

    private func updateBottomDockHeight() {
        bottomDockHeight?.constant = bottomToolbarHeight + view.safeAreaInsets.bottom
    }

    @objc func enterDrawMode() {
        interactionMode = .draw
        closeTextSubsheet()
        commitActiveTextEditing()
        deselectAllTextBoxes()
        setTextCustomizePanelVisible(false)
        updateModeButtonChrome()
        syncDrawingToolsVisibility()
        DispatchQueue.main.async { [weak self] in
            self?.elevateMarkupChrome()
        }
    }

    @objc func closeTextCustomizePanel() {
        closeTextSubsheet()
        commitActiveTextEditing()
        setTextCustomizePanelVisible(false)
        syncDrawingToolsVisibility()
    }

    // MARK: - Canva-style sub-sheets (open from toolbar chips, Close returns to main bar)

    func closeTextSubsheet() {
        isTextSubsheetOpen = false
        subsheetHost.subviews.forEach { $0.removeFromSuperview() }
        subsheetHost.isHidden = true
        textCustomizeScroll.isHidden = false
        panelTitleLabel?.text = "Text"
        panelDoneButton?.setTitle("Close", for: .normal)
        if isTextCustomizePanelVisible {
            customizePanelHeight.constant = textCustomizeCompactHeight
            UIView.animate(withDuration: 0.36, delay: 0, usingSpringWithDamping: 0.86, initialSpringVelocity: 0) {
                self.view.layoutIfNeeded()
            }
        }
    }

    private func presentTextSubsheet(title: String, body: UIView) {
        isTextSubsheetOpen = true
        subsheetHost.subviews.forEach { $0.removeFromSuperview() }
        panelTitleLabel?.text = title
        panelTitleLabel?.textColor = MarkupEditorChromeUIKit.primaryText(traitCollection)
        panelDoneButton?.setTitle("Close", for: .normal)
        panelDoneButton?.setTitleColor(MarkupEditorChromeUIKit.headerActionText(traitCollection), for: .normal)
        textCustomizeScroll.isHidden = true
        subsheetHost.isHidden = false
        subsheetHost.backgroundColor = .clear
        body.translatesAutoresizingMaskIntoConstraints = false
        subsheetHost.addSubview(body)
        NSLayoutConstraint.activate([
            body.topAnchor.constraint(equalTo: subsheetHost.topAnchor),
            body.leadingAnchor.constraint(equalTo: subsheetHost.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: subsheetHost.trailingAnchor),
            body.bottomAnchor.constraint(equalTo: subsheetHost.bottomAnchor),
        ])
        customizePanelHeight.constant = textCustomizeSubsheetHeight
        elevateMarkupChrome()
        DSUIKit.animateOperationalSheet { self.view.layoutIfNeeded() }
    }

    private func wrapSubsheetScroll(_ stack: UIStackView) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.showsVerticalScrollIndicator = true
        scroll.backgroundColor = .clear
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 2),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -6),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
        ])
        return scroll
    }

    @objc func openColorsSubsheet() {
        guard activeBox() != nil else { return }
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.addArrangedSubview(subsheetNavRow(
            title: "Text color",
            detail: "Solid & gradient",
            action: #selector(openTextColorSubsheet)
        ))
        stack.addArrangedSubview(subsheetNavRow(
            title: "Text box background",
            detail: "Fill, style & gradient",
            action: #selector(openBoxBackgroundSubsheet)
        ))
        presentTextSubsheet(title: "Colors", body: wrapSubsheetScroll(stack))
    }

    @objc func openTextColorSubsheet() {
        guard let box = activeBox() else { return }
        let stack = UIStackView()

        stack.addArrangedSubview(subsheetSectionTitle("Text color"))
        stack.addArrangedSubview(colorPickerRow(
            leadingTitle: "Color",
            color: box.elementStyle.textColor,
            action: #selector(pickCaptionColor)
        ))
        stack.addArrangedSubview(colorPickerRow(
            leadingTitle: "Gradient",
            color: box.elementStyle.textGradientEndColor,
            action: #selector(pickTextGradientEndColor)
        ))

        stack.addArrangedSubview(subsheetSectionTitle("Gradient presets"))
        stack.addArrangedSubview(labeledGradientPresetList(MarkupTextColorPresets.textGradients) { [weak self] index in
            self?.applyTextGradientPresetTag(index)
        })

        stack.addArrangedSubview(subsheetSectionTitle("Outline"))
        stack.addArrangedSubview(colorPickerRow(
            leadingTitle: "Color",
            color: box.elementStyle.outlineColor,
            action: #selector(pickTextOutlineColor)
        ))
        stack.addArrangedSubview(spacingStepperRow(
            title: "Outline width",
            value: Int(box.elementStyle.outlineWidth.rounded()),
            unitSuffix: "pt",
            onChange: { [weak self] v in
                guard let box = self?.activeBox() else { return }
                box.elementStyle.outlineWidth = CGFloat(v)
                self?.markupStyleDidChange()
            }
        ))

        presentTextSubsheet(title: "Text color", body: wrapSubsheetScroll(stack))
    }

    @objc func openBoxBackgroundSubsheet() {
        guard let box = activeBox() else { return }
        let stack = UIStackView()

        stack.addArrangedSubview(subsheetSectionTitle("Box fill"))
        stack.addArrangedSubview(colorPickerRow(
            leadingTitle: "Color",
            color: box.fillColor,
            action: #selector(pickBoxBackgroundColor)
        ))
        stack.addArrangedSubview(colorPickerRow(
            leadingTitle: "Gradient",
            color: box.fillSecondaryColor,
            action: #selector(pickBoxSecondaryColor)
        ))

        stack.addArrangedSubview(subsheetSectionTitle("Style"))
        let styleRow = UIStackView()
        styleRow.axis = .horizontal
        styleRow.spacing = 8
        styleRow.distribution = .fillEqually
        for (title, style, sel) in [
            ("Clear", MarkupTextBackgroundStyle.transparent, #selector(setBgTransparent)),
            ("Solid", MarkupTextBackgroundStyle.solid, #selector(setBgSolid)),
            ("Glass", MarkupTextBackgroundStyle.glass, #selector(setBgGlass)),
            ("Gradient", MarkupTextBackgroundStyle.gradient, #selector(setBgGradient)),
        ] {
            styleRow.addArrangedSubview(subsheetChipButton(title: title, action: sel, selected: box.backgroundStyle == style))
        }
        stack.addArrangedSubview(styleRow)

        stack.addArrangedSubview(subsheetSectionTitle("Gradient presets"))
        stack.addArrangedSubview(labeledGradientPresetList(MarkupTextColorPresets.boxGradients) { [weak self] index in
            self?.applyBoxGradientPresetTag(index)
        })

        let opacityRow = UIStackView()
        opacityRow.axis = .horizontal
        opacityRow.spacing = 10
        opacityRow.alignment = .center
        let opacityLabel = subsheetSectionTitle("Opacity \(Int(box.fillOpacity * 100))%")
        opacityLabel.setContentHuggingPriority(.required, for: .horizontal)
        let slider = UISlider()
        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.value = Float(box.fillOpacity)
        slider.tintColor = MarkupEditorChromeUIKit.sliderTint(traitCollection)
        slider.addAction(UIAction { [weak box] _ in
            guard let box else { return }
            box.fillOpacity = CGFloat(slider.value)
            box.applyBackgroundStyle()
            opacityLabel.text = "Opacity \(Int(box.fillOpacity * 100))%"
        }, for: .valueChanged)
        opacityRow.addArrangedSubview(opacityLabel)
        opacityRow.addArrangedSubview(slider)
        stack.addArrangedSubview(opacityRow)

        presentTextSubsheet(title: "Text box background", body: wrapSubsheetScroll(stack))
    }

    @objc func openAlignmentSubsheet() {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 10
        stack.addArrangedSubview(subsheetSectionTitle("Align text inside the box"))
        for (title, sel) in [
            ("Left", #selector(alignTextLeft)),
            ("Center", #selector(alignTextCenter)),
            ("Right", #selector(alignTextRight)),
        ] {
            stack.addArrangedSubview(subsheetChipButton(title: title, action: sel, height: 44))
        }
        presentTextSubsheet(title: "Alignment", body: stack)
    }

    @objc func openSpacingSubsheet() {
        guard let box = activeBox() else { return }
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 14
        stack.addArrangedSubview(subsheetSectionTitle("Inner padding"))
        stack.addArrangedSubview(subsheetCaptionLabel("Values are in points (pt) — the same unit as font size. Typical caption spacing: 10–12 pt top/bottom, 14–18 pt left/right."))
        stack.addArrangedSubview(spacingStepperRow(
            title: "Top",
            value: Int(box.contentPadding.top),
            onChange: { [weak box] v in box?.contentPadding.top = CGFloat(v); box?.applyContentInsetsToViews(); self.markupStyleDidChange() }
        ))
        stack.addArrangedSubview(spacingStepperRow(
            title: "Bottom",
            value: Int(box.contentPadding.bottom),
            onChange: { [weak box] v in box?.contentPadding.bottom = CGFloat(v); box?.applyContentInsetsToViews(); self.markupStyleDidChange() }
        ))
        stack.addArrangedSubview(spacingStepperRow(
            title: "Left",
            value: Int(box.contentPadding.left),
            onChange: { [weak box] v in box?.contentPadding.left = CGFloat(v); box?.applyContentInsetsToViews(); self.markupStyleDidChange() }
        ))
        stack.addArrangedSubview(spacingStepperRow(
            title: "Right",
            value: Int(box.contentPadding.right),
            onChange: { [weak box] v in box?.contentPadding.right = CGFloat(v); box?.applyContentInsetsToViews(); self.markupStyleDidChange() }
        ))
        stack.addArrangedSubview(subsheetSectionTitle("Side margin"))
        stack.addArrangedSubview(subsheetCaptionLabel("Extra space outside the colored box, in points (pt)."))
        stack.addArrangedSubview(spacingStepperRow(
            title: "Left & right",
            value: Int(box.marginHorizontal),
            onChange: { [weak box] v in box?.marginHorizontal = CGFloat(v); box?.applyContentInsetsToViews(); self.markupStyleDidChange() }
        ))
        let wrap = UIScrollView()
        wrap.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: wrap.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: wrap.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: wrap.contentLayoutGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: wrap.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: wrap.frameLayoutGuide.widthAnchor),
        ])
        presentTextSubsheet(title: "Spacing", body: wrap)
    }

    @objc func openTextSizeSubsheet() {
        guard let box = activeBox() else { return }
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 16
        stack.alignment = .center
        stack.distribution = .equalCentering

        let minus = UIButton(type: .system)
        minus.setImage(UIImage(systemName: "minus.circle.fill"), for: .normal)
        minus.addTarget(self, action: #selector(shrinkCaptionFontForSubsheet), for: .touchUpInside)
        let label = UILabel()
        label.font = .systemFont(ofSize: 28, weight: .bold)
        label.textAlignment = .center
        label.text = "\(Int(box.elementStyle.fontSize)) pt"
        label.tag = 9001
        let plus = UIButton(type: .system)
        plus.setImage(UIImage(systemName: "plus.circle.fill"), for: .normal)
        plus.addTarget(self, action: #selector(growCaptionFontForSubsheet), for: .touchUpInside)
        stack.addArrangedSubview(minus)
        stack.addArrangedSubview(label)
        stack.addArrangedSubview(plus)
        presentTextSubsheet(title: "Font size", body: stack)
    }

    @objc private func growCaptionFontForSubsheet() {
        growCaptionFont()
        refreshFontSizeSubsheetLabel()
    }

    @objc private func shrinkCaptionFontForSubsheet() {
        shrinkCaptionFont()
        refreshFontSizeSubsheetLabel()
    }

    private func refreshFontSizeSubsheetLabel() {
        if let label = subsheetHost.viewWithTag(9001) as? UILabel, let box = activeBox() {
            label.text = "\(Int(box.elementStyle.fontSize)) pt"
        }
    }

    private func subsheetSectionTitle(_ text: String) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = DSUIKit.microFont
        l.textColor = MarkupEditorChromeUIKit.captionLabel(traitCollection)
        l.numberOfLines = 0
        return l
    }

    private func subsheetCaptionLabel(_ text: String) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = DSUIKit.captionFont
        l.textColor = MarkupEditorChromeUIKit.captionLabel(traitCollection)
        l.numberOfLines = 2
        return l
    }

    private func subsheetNavRow(title: String, detail: String, action: Selector) -> UIButton {
        let btn = UIButton(type: .system)
        btn.contentHorizontalAlignment = .leading
        btn.backgroundColor = MarkupEditorChromeUIKit.chipBackground(traitCollection)
        btn.layer.cornerRadius = DS.Radius.chip
        btn.layer.cornerCurve = .continuous
        btn.layer.borderWidth = 1
        btn.layer.borderColor = MarkupEditorChromeUIKit.divider(traitCollection).cgColor
        btn.heightAnchor.constraint(greaterThanOrEqualToConstant: 46).isActive = true
        var config = UIButton.Configuration.plain()
        config.title = title
        config.subtitle = detail
        config.image = UIImage(systemName: "chevron.right")
        config.imagePlacement = .trailing
        config.imagePadding = 6
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 10)
        config.baseForegroundColor = MarkupEditorChromeUIKit.primaryText(traitCollection)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var out = incoming
            out.font = .systemFont(ofSize: 14, weight: .semibold)
            return out
        }
        let captionInk = MarkupEditorChromeUIKit.captionLabel(traitCollection)
        config.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var out = incoming
            out.font = .systemFont(ofSize: 11, weight: .medium)
            out.foregroundColor = captionInk
            return out
        }
        btn.configuration = config
        btn.addTarget(self, action: action, for: .touchUpInside)
        DSUIKit.installPressFeedback(on: btn, scale: DS.Motion.pressScaleCompact)
        return btn
    }

    private func subsheetChipButton(title: String, action: Selector, height: CGFloat = 32, selected: Bool = false) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.setTitleColor(MarkupEditorChromeUIKit.controlLabel(traitCollection), for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        b.backgroundColor = selected
            ? MarkupEditorChromeUIKit.chipSelected(traitCollection)
            : MarkupEditorChromeUIKit.chipBackground(traitCollection)
        b.layer.cornerRadius = DS.Radius.chip
        b.layer.cornerCurve = .continuous
        b.layer.borderWidth = selected ? 1.5 : 1
        b.layer.borderColor = (selected
            ? MarkupEditorChromeUIKit.accent(traitCollection)
            : MarkupEditorChromeUIKit.divider(traitCollection)).cgColor
        b.heightAnchor.constraint(equalToConstant: height).isActive = true
        b.addTarget(self, action: action, for: .touchUpInside)
        DSUIKit.installPressFeedback(on: b, scale: DS.Motion.pressScaleCompact)
        return b
    }

    private func colorPickerRow(leadingTitle: String, color: UIColor, action: Selector) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center
        let title = UILabel()
        title.text = leadingTitle
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = MarkupEditorChromeUIKit.controlLabel(traitCollection)
        title.widthAnchor.constraint(equalToConstant: 76).isActive = true
        let swatch = UIButton(type: .custom)
        swatch.backgroundColor = color
        swatch.layer.cornerRadius = DS.Radius.chip
        swatch.layer.borderWidth = 1.5
        swatch.layer.borderColor = MarkupEditorChromeUIKit.divider(traitCollection).cgColor
        swatch.widthAnchor.constraint(equalToConstant: 30).isActive = true
        swatch.heightAnchor.constraint(equalToConstant: 30).isActive = true
        swatch.addTarget(self, action: action, for: .touchUpInside)
        DSUIKit.installPressFeedback(on: swatch, scale: DS.Motion.pressScaleIcon)
        let hint = subsheetCaptionLabel("Color wheel")
        row.addArrangedSubview(title)
        row.addArrangedSubview(swatch)
        row.addArrangedSubview(hint)
        return row
    }

    private func spacingStepperRow(
        title: String,
        value: Int,
        unitSuffix: String = "pt",
        maxValue: Int = 48,
        onChange: @escaping (Int) -> Void
    ) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 10
        row.alignment = .center
        row.backgroundColor = MarkupEditorChromeUIKit.chipBackground(traitCollection)
        row.layer.cornerRadius = 12
        row.layer.cornerCurve = .continuous
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        let ink = MarkupEditorChromeUIKit.controlLabel(traitCollection)
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = ink
        label.widthAnchor.constraint(equalToConstant: 110).isActive = true
        let valueLabel = UILabel()
        valueLabel.text = "\(value) \(unitSuffix)"
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .bold)
        valueLabel.textColor = ink
        valueLabel.textAlignment = .center
        valueLabel.widthAnchor.constraint(equalToConstant: 56).isActive = true
        let minus = subsheetStepperButton(symbol: "minus")
        let plus = subsheetStepperButton(symbol: "plus")
        var current = value
        minus.addAction(UIAction { _ in
            current = max(0, current - 1)
            valueLabel.text = "\(current) \(unitSuffix)"
            onChange(current)
        }, for: .touchUpInside)
        plus.addAction(UIAction { _ in
            current = min(maxValue, current + 1)
            valueLabel.text = "\(current) \(unitSuffix)"
            onChange(current)
        }, for: .touchUpInside)
        row.addArrangedSubview(label)
        row.addArrangedSubview(minus)
        row.addArrangedSubview(valueLabel)
        row.addArrangedSubview(plus)
        return row
    }

    private func labeledGradientPresetList(
        _ presets: [(String, UIColor, UIColor)],
        onPick: @escaping (Int) -> Void
    ) -> UIView {
        let list = UIStackView()
        list.axis = .vertical
        list.spacing = 8
        for (index, preset) in presets.enumerated() {
            let row = UIButton(type: .system)
            row.contentHorizontalAlignment = .leading
            row.backgroundColor = MarkupEditorChromeUIKit.chipBackground(traitCollection)
            row.layer.cornerRadius = 12
            row.layer.cornerCurve = .continuous
            row.layer.borderWidth = 1
            row.layer.borderColor = MarkupEditorChromeUIKit.divider(traitCollection).cgColor
            row.heightAnchor.constraint(equalToConstant: 48).isActive = true

            var config = UIButton.Configuration.plain()
            config.title = preset.0
            config.image = gradientSwatchImage(start: preset.1, end: preset.2, size: CGSize(width: 56, height: 28))
            config.imagePlacement = .trailing
            config.imagePadding = 10
            config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 12)
            config.baseForegroundColor = MarkupEditorChromeUIKit.primaryText(traitCollection)
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var out = incoming
                out.font = .systemFont(ofSize: 14, weight: .semibold)
                return out
            }
            row.configuration = config
            row.tag = index
            row.addAction(UIAction { [weak row] _ in
                guard let row else { return }
                onPick(row.tag)
            }, for: .touchUpInside)
            list.addArrangedSubview(row)
        }
        return list
    }

    private func gradientSwatchImage(start: UIColor, end: UIColor, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 8)
            path.addClip()
            let colors = [start.cgColor, end.cgColor] as CFArray
            if let g = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 1]
            ) {
                ctx.cgContext.drawLinearGradient(
                    g,
                    start: CGPoint(x: rect.minX, y: rect.midY),
                    end: CGPoint(x: rect.maxX, y: rect.midY),
                    options: []
                )
            }
        }
    }

    private func subsheetStepperButton(symbol: String) -> UIButton {
        let b = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        b.setImage(UIImage(systemName: symbol, withConfiguration: cfg), for: .normal)
        b.tintColor = MarkupEditorChromeUIKit.controlLabel(traitCollection)
        b.backgroundColor = MarkupEditorChromeUIKit.panelBackground(traitCollection)
        b.layer.cornerRadius = 8
        b.layer.borderWidth = 1
        b.layer.borderColor = MarkupEditorChromeUIKit.divider(traitCollection).cgColor
        b.widthAnchor.constraint(equalToConstant: 36).isActive = true
        b.heightAnchor.constraint(equalToConstant: 36).isActive = true
        return b
    }

    private func colorSwatchGrid(_ colors: [UIColor], onPick: @escaping (UIColor) -> Void) -> UIView {
        let grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = 10
        let columns = 6
        for chunkStart in stride(from: 0, to: colors.count, by: columns) {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 10
            row.alignment = .center
            let end = min(chunkStart + columns, colors.count)
            for i in chunkStart..<end {
                let btn = UIButton(type: .custom)
                btn.backgroundColor = colors[i]
                btn.layer.cornerRadius = 16
                btn.layer.borderWidth = 2
                btn.layer.borderColor = MarkupEditorChromeUIKit.divider(traitCollection).cgColor
                btn.widthAnchor.constraint(equalToConstant: 32).isActive = true
                btn.heightAnchor.constraint(equalToConstant: 32).isActive = true
                let picked = colors[i]
                btn.addAction(UIAction { _ in onPick(picked) }, for: .touchUpInside)
                row.addArrangedSubview(btn)
            }
            let spacer = UIView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            row.addArrangedSubview(spacer)
            grid.addArrangedSubview(row)
        }
        return grid
    }

    private func gradientPresetRow(
        _ presets: [(String, UIColor, UIColor)],
        tagBase: Int,
        onPick: @escaping (Int) -> Void
    ) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 10
        for (i, (_, c1, c2)) in presets.enumerated() {
            let btn = UIButton(type: .custom)
            btn.tag = tagBase + i
            btn.layer.cornerRadius = 16
            btn.clipsToBounds = true
            btn.widthAnchor.constraint(equalToConstant: 36).isActive = true
            btn.heightAnchor.constraint(equalToConstant: 36).isActive = true
            let g = CAGradientLayer()
            g.frame = CGRect(x: 0, y: 0, width: 36, height: 36)
            g.colors = [c1.cgColor, c2.cgColor]
            g.startPoint = CGPoint(x: 0, y: 0.5)
            g.endPoint = CGPoint(x: 1, y: 0.5)
            g.cornerRadius = 16
            btn.layer.insertSublayer(g, at: 0)
            btn.addAction(UIAction { [weak btn] _ in
                guard let btn else { return }
                onPick(btn.tag - tagBase)
            }, for: .touchUpInside)
            row.addArrangedSubview(btn)
        }
        return row
    }

    private func applyTextGradientPresetTag(_ index: Int) {
        let presets = MarkupTextColorPresets.textGradients
        guard index >= 0, index < presets.count, let box = activeBox() else { return }
        let p = presets[index]
        box.elementStyle.textColor = p.1
        box.elementStyle.textGradientEndColor = p.2
        box.elementStyle.usesTextGradient = true
        markupStyleDidChange()
    }

    private func applyBoxGradientPresetTag(_ index: Int) {
        let presets = MarkupTextColorPresets.boxGradients
        guard index >= 0, index < presets.count, let box = activeBox() else { return }
        let p = presets[index]
        box.fillColor = p.1
        box.fillSecondaryColor = p.2
        box.fillOpacity = 1.0
        box.backgroundStyle = .gradient
        box.applyBackgroundStyle()
        markupStyleDidChange()
    }

    private func setTextCustomizePanelVisible(_ visible: Bool) {
        isTextCustomizePanelVisible = visible
        textCustomizePanel.isHidden = !visible
        customizePanelHeight.constant = visible ? (isTextSubsheetOpen ? textCustomizeSubsheetHeight : textCustomizeCompactHeight) : 0
        imageBottomToToolbar.isActive = !visible
        imageBottomToCustomize.isActive = visible

        if visible {
            if let box = activeBox() {
                selectTextBox(box, beginEditing: false)
            }
            canvaTextToolbar.refreshFor(activeBox())
        }
        syncDrawingToolsVisibility()

        // Matches the SwiftUI slide-up sheets' spring (response 0.36, damping 0.86).
        UIView.animate(withDuration: 0.36, delay: 0, usingSpringWithDamping: 0.86, initialSpringVelocity: 0) {
            self.view.layoutIfNeeded()
        }
        if visible {
            ensureActiveTextBoxVisible(animated: true)
            elevateMarkupChrome()
        }
    }

    @objc func focusSelectedTextBox() {
        guard let box = activeBox() else { return }
        selectTextBox(box, beginEditing: true)
    }

    func presentAuxiliary(_ controller: UIViewController) {
        syncDrawingToolsVisibility()
        let presenter = navigationController ?? self
        controller.modalPresentationStyle = .pageSheet
        if let sheet = controller.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        let presentBlock = { presenter.present(controller, animated: true) }
        if presenter.presentedViewController != nil {
            presenter.dismiss(animated: false, completion: presentBlock)
        } else {
            presentBlock()
        }
    }

    func isTextBoxSelected(_ box: MarkupTextBoxView) -> Bool {
        selectedTextBox === box
    }

    @objc private func canvasBackgroundTapped(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: overlayHost)
        guard !textBoxes.contains(where: { $0.frame.contains(point) }) else { return }
        interactionMode = .idle
        deselectAllTextBoxes()
        setTextCustomizePanelVisible(false)
        updateModeButtonChrome()
        syncDrawingToolsVisibility()
    }

    private func deselectAllTextBoxes() {
        selectedTextBox?.endEditingText()
        selectedTextBox?.setSelected(false)
        selectedTextBox = nil
        canvaTextToolbar.refreshFor(nil)
    }

    private func setDrawingToolsVisible(_ visible: Bool) {
        guard let picker = toolPicker else { return }
        if visible {
            picker.addObserver(canvas)
            canvas.becomeFirstResponder()
            picker.setVisible(true, forFirstResponder: canvas)
        } else {
            picker.setVisible(false, forFirstResponder: canvas)
            canvas.resignFirstResponder()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func registerKeyboardObservers() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(keyboardWillChange(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        center.addObserver(self, selector: #selector(keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    @objc private func keyboardWillChange(_ note: Notification) {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let local = view.convert(frame, from: nil)
        keyboardOverlap = max(0, view.bounds.maxY - local.minY)
        if isEditingText { ensureActiveTextBoxVisible(animated: true) }
    }

    @objc private func keyboardWillHide(_ note: Notification) {
        keyboardOverlap = 0
    }

    func textBoxDidBeginEditing(_ box: MarkupTextBoxView) {
        isEditingText = true
        interactionMode = .text
        selectTextBox(box, beginEditing: false)
        canvaTextToolbar.refreshFor(box)
        updateModeButtonChrome()
        syncDrawingToolsVisibility()
        ensureActiveTextBoxVisible(animated: false)
    }

    func textBoxDidEndEditing(_ box: MarkupTextBoxView) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.textBoxes.contains(where: { $0.textView.isFirstResponder }) {
                self.isEditingText = true
                return
            }
            self.isEditingText = false
            box.setSelected(self.selectedTextBox === box)
            self.syncDrawingToolsVisibility()
        }
    }

    func ensureActiveTextBoxVisible(animated: Bool) {
        guard let box = selectedTextBox ?? textBoxes.first(where: { $0.textView.isFirstResponder }) else { return }
        let boxInView = box.convert(box.bounds, to: view)
        let panelH = isTextCustomizePanelVisible
            ? (isTextSubsheetOpen ? textCustomizeSubsheetHeight : textCustomizeCompactHeight)
            : 0
        let safeBottom = view.bounds.height - keyboardOverlap - bottomToolbarHeight - panelH - 8
        guard boxInView.maxY > safeBottom else {
            constrainTextBox(box)
            return
        }
        let delta = boxInView.maxY - safeBottom
        var center = box.center
        center.y -= delta
        box.center = center
        constrainTextBox(box)
    }

    @objc private func addTextBoxTapped() {
        enterTextMode()
    }

    func addTextBox(focus: Bool) {
        interactionMode = .text
        let box = MarkupTextBoxView(frame: .zero)
        box.markupHost = self
        let ir = imageRectInOverlay()
        let w = min(ir.width - 16, 280)
        let h = max(56, MarkupTextBoxView.minimumHeight(for: box.elementStyle.fontSize, padding: box.contentPadding) + 16)
        box.frame = CGRect(x: ir.midX - w / 2, y: ir.midY - h / 2, width: w, height: h)
        overlayHost.addSubview(box)
        textBoxes.append(box)
        selectTextBox(box, beginEditing: focus)
        updateModeButtonChrome()
        syncDrawingToolsVisibility()
    }

    func selectTextBox(_ box: MarkupTextBoxView, beginEditing: Bool = false) {
        interactionMode = .text
        if selectedTextBox !== box {
            selectedTextBox?.endEditingText()
            selectedTextBox?.setSelected(false)
        }
        selectedTextBox = box
        box.setSelected(true)
        if beginEditing {
            box.beginEditing()
        }
        if !isTextCustomizePanelVisible {
            setTextCustomizePanelVisible(true)
        } else {
            canvaTextToolbar.refreshFor(box)
            syncDrawingToolsVisibility()
        }
        updateModeButtonChrome()
    }

    @objc func deleteSelectedTextBox() {
        guard let box = selectedTextBox else { return }
        removeTextBox(box)
    }

    private func removeTextBox(_ box: MarkupTextBoxView) {
        textBoxes.removeAll { $0 === box }
        box.removeFromSuperview()
        if selectedTextBox === box {
            selectedTextBox = nil
            canvaTextToolbar.refreshFor(nil)
        }
        if textBoxes.isEmpty, isTextCustomizePanelVisible {
            setTextCustomizePanelVisible(false)
        }
        syncDrawingToolsVisibility()
    }

    @objc func duplicateSelectedTextBox() {
        guard let source = activeBox() else { return }
        duplicateTextBox(source)
    }

    func duplicateTextBox(_ source: MarkupTextBoxView) {
        let box = MarkupTextBoxView(frame: .zero)
        box.markupHost = self
        box.copyState(from: source)
        var f = source.frame
        f.origin.x += 14
        f.origin.y += 14
        box.frame = f
        overlayHost.addSubview(box)
        textBoxes.append(box)
        selectTextBox(box, beginEditing: false)
        resizeTextBox(box)
        constrainTextBox(box)
    }

    func showTextBoxActionMenu(for box: MarkupTextBoxView, sourceView: UIView) {
        selectTextBox(box, beginEditing: false)
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Edit text", style: .default) { [weak self, weak box] _ in
            guard let self, let box else { return }
            self.selectTextBox(box, beginEditing: true)
        })
        sheet.addAction(UIAlertAction(title: "Duplicate", style: .default) { [weak self, weak box] _ in
            guard let self, let box else { return }
            self.duplicateTextBox(box)
        })
        sheet.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self, weak box] _ in
            guard let self, let box else { return }
            self.removeTextBox(box)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = sourceView
            pop.sourceRect = sourceView.bounds
        }
        present(sheet, animated: true)
    }

    func resizeTextBox(_ box: MarkupTextBoxView) {
        box.resizeToFitText(maxWidth: currentMaxTextWidth, maxHeight: currentMaxTextHeight)
        constrainTextBox(box)
    }

    func constrainTextBox(_ box: MarkupTextBoxView) {
        let ir = imageRectInOverlay()
        guard ir.width > 20, ir.height > 20 else { return }
        var f = box.frame
        f.size.width = min(f.width, ir.width - 8)
        f.size.height = min(max(f.height, MarkupTextBoxView.minimumHeight(for: box.baseFontSize, padding: box.contentPadding)), ir.height - 8)
        if f.midX < ir.minX + f.width / 2 { f.origin.x = ir.minX + 4 }
        if f.midX > ir.maxX - f.width / 2 { f.origin.x = ir.maxX - f.width - 4 }
        if f.midY < ir.minY + f.height / 2 { f.origin.y = ir.minY + 4 }
        if f.midY > ir.maxY - f.height / 2 { f.origin.y = ir.maxY - f.height - 4 }
        box.frame = f
    }

    func imageRectInOverlay() -> CGRect {
        aspectFitRect(imageSize: baseImage.size, in: overlayHost.bounds)
    }

    private func activeBox() -> MarkupTextBoxView? {
        if let selectedTextBox { return selectedTextBox }
        if let editing = textBoxes.first(where: { $0.textView.isFirstResponder }) { return editing }
        return textBoxes.last
    }

    private func markupStyleDidChange() {
        guard let box = activeBox() else { return }
        box.refreshFromStyle()
        if box.isEditingText {
            box.applyStyleToEditorPreservingSelection()
        }
        box.applyBackgroundStyle()
        resizeTextBox(box)
        canvaTextToolbar.refreshFor(box)
    }

    @objc fileprivate func dismissCaptionKeyboard() {
        closeTextCustomizePanel()
    }

    @objc fileprivate func shrinkCaptionFont() {
        guard let box = activeBox() else { return }
        box.elementStyle.fontSize = max(12, box.elementStyle.fontSize - 2)
        markupStyleDidChange()
    }

    @objc fileprivate func growCaptionFont() {
        guard let box = activeBox() else { return }
        box.elementStyle.fontSize = min(72, box.elementStyle.fontSize + 2)
        markupStyleDidChange()
    }

    @objc fileprivate func pickCaptionColor() {
        colorPickTarget = .text
        let picker = UIColorPickerViewController()
        picker.selectedColor = activeBox()?.elementStyle.textColor ?? .white
        picker.supportsAlpha = false
        picker.delegate = self
        presentAuxiliary(picker)
    }

    @objc fileprivate func pickTextGradientEndColor() {
        colorPickTarget = .textGradientEnd
        let picker = UIColorPickerViewController()
        picker.selectedColor = activeBox()?.elementStyle.textGradientEndColor ?? .white
        picker.supportsAlpha = false
        picker.delegate = self
        presentAuxiliary(picker)
    }

    @objc fileprivate func pickTextOutlineColor() {
        colorPickTarget = .textOutline
        let picker = UIColorPickerViewController()
        picker.selectedColor = activeBox()?.elementStyle.outlineColor ?? .black
        picker.supportsAlpha = false
        picker.delegate = self
        presentAuxiliary(picker)
    }

    @objc fileprivate func pickBoxBackgroundColor() {
        colorPickTarget = .boxPrimary
        let picker = UIColorPickerViewController()
        picker.selectedColor = activeBox()?.fillColor ?? .black
        picker.supportsAlpha = true
        picker.delegate = self
        presentAuxiliary(picker)
    }

    @objc fileprivate func pickBoxSecondaryColor() {
        colorPickTarget = .boxSecondary
        let picker = UIColorPickerViewController()
        picker.selectedColor = activeBox()?.fillSecondaryColor ?? .darkGray
        picker.supportsAlpha = true
        picker.delegate = self
        presentAuxiliary(picker)
    }

    @objc fileprivate func applyTextGradientPreset(_ sender: UIButton) {
        let presets = MarkupTextColorPresets.textGradients
        guard sender.tag >= 0, sender.tag < presets.count, let box = activeBox() else { return }
        let p = presets[sender.tag]
        box.elementStyle.textColor = p.1
        box.elementStyle.textGradientEndColor = p.2
        box.elementStyle.usesTextGradient = true
        markupStyleDidChange()
    }

    @objc fileprivate func applyBoxGradientPreset(_ sender: UIButton) {
        let presets = MarkupTextColorPresets.boxGradients
        guard sender.tag >= 0, sender.tag < presets.count, let box = activeBox() else { return }
        let p = presets[sender.tag]
        box.fillColor = p.1
        box.fillSecondaryColor = p.2
        box.backgroundStyle = .gradient
        markupStyleDidChange()
    }

    @objc fileprivate func shrinkPaddingHorizontal() { adjustPadding(horizontal: -2) }
    @objc fileprivate func growPaddingHorizontal() { adjustPadding(horizontal: 2) }
    @objc fileprivate func shrinkPaddingVertical() { adjustPadding(vertical: -2) }
    @objc fileprivate func growPaddingVertical() { adjustPadding(vertical: 2) }
    @objc fileprivate func shrinkMarginHorizontal() { adjustMargin(-2) }
    @objc fileprivate func growMarginHorizontal() { adjustMargin(2) }

    private func adjustPadding(horizontal: CGFloat = 0, vertical: CGFloat = 0) {
        guard let box = activeBox() else { return }
        if horizontal != 0 {
            box.contentPadding.left = max(0, min(48, box.contentPadding.left + horizontal))
            box.contentPadding.right = max(0, min(48, box.contentPadding.right + horizontal))
        }
        if vertical != 0 {
            box.contentPadding.top = max(0, min(48, box.contentPadding.top + vertical))
            box.contentPadding.bottom = max(0, min(48, box.contentPadding.bottom + vertical))
        }
        box.applyContentInsetsToViews()
        markupStyleDidChange()
    }

    private func adjustMargin(_ delta: CGFloat) {
        guard let box = activeBox() else { return }
        box.marginHorizontal = max(0, min(32, box.marginHorizontal + delta))
        box.applyContentInsetsToViews()
        markupStyleDidChange()
    }

    @objc fileprivate func pickCaptionFontFace() {
        let vc = UIFontPickerViewController()
        vc.delegate = self
        presentAuxiliary(vc)
    }

    @objc fileprivate func setBgTransparent() {
        guard let box = activeBox() else { return }
        box.backgroundStyle = .transparent
        markupStyleDidChange()
    }

    @objc fileprivate func setBgSolid() {
        guard let box = activeBox() else { return }
        box.backgroundStyle = .solid
        markupStyleDidChange()
    }

    @objc fileprivate func setBgGradient() {
        guard let box = activeBox() else { return }
        box.backgroundStyle = .gradient
        box.fillOpacity = 1.0
        box.applyBackgroundStyle()
        markupStyleDidChange()
    }

    @objc fileprivate func setBgGlass() {
        guard let box = activeBox() else { return }
        box.backgroundStyle = .glass
        markupStyleDidChange()
    }

    @objc fileprivate func bgOpacityChanged(_ slider: UISlider) {
        guard let box = activeBox() else { return }
        box.fillOpacity = CGFloat(slider.value)
        box.applyBackgroundStyle()
        canvaTextToolbar.refreshFor(box)
    }

    func fontPickerViewControllerDidPickFont(_ viewController: UIFontPickerViewController) {
        guard let desc = viewController.selectedFontDescriptor, let box = activeBox() else {
            viewController.dismiss(animated: true)
            return
        }
        box.elementStyle.fontDescriptor = desc
        viewController.dismiss(animated: true)
        markupStyleDidChange()
    }

    func fontPickerViewControllerDidCancel(_ viewController: UIFontPickerViewController) {
        viewController.dismiss(animated: true)
    }

    @objc fileprivate func toggleBold() {
        activeBox()?.elementStyle.isBold.toggle()
        markupStyleDidChange()
    }

    @objc fileprivate func toggleItalic() {
        activeBox()?.elementStyle.isItalic.toggle()
        markupStyleDidChange()
    }

    @objc fileprivate func alignTextLeft() {
        activeBox()?.elementStyle.alignment = .left
        markupStyleDidChange()
        closeTextSubsheet()
    }

    @objc fileprivate func alignTextCenter() {
        activeBox()?.elementStyle.alignment = .center
        markupStyleDidChange()
        closeTextSubsheet()
    }

    @objc fileprivate func alignTextRight() {
        activeBox()?.elementStyle.alignment = .right
        markupStyleDidChange()
        closeTextSubsheet()
    }

    @objc fileprivate func toggleMarkupUnderline() {
        activeBox()?.elementStyle.isUnderline.toggle()
        markupStyleDidChange()
    }

    @objc fileprivate func toggleMarkupStrikethrough() {
        activeBox()?.elementStyle.isStrikethrough.toggle()
        markupStyleDidChange()
    }

    func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
        applyPickedColor(viewController.selectedColor)
        viewController.dismiss(animated: true)
    }

    func colorPickerViewControllerDidSelectColor(_ viewController: UIColorPickerViewController) {
        applyPickedColor(viewController.selectedColor)
    }

    private func applyPickedColor(_ color: UIColor) {
        guard let box = activeBox() else { return }
        switch colorPickTarget {
        case .text:
            box.elementStyle.textColor = color
            box.elementStyle.usesTextGradient = false
        case .textGradientEnd:
            box.elementStyle.textGradientEndColor = color
            box.elementStyle.usesTextGradient = true
        case .textOutline:
            box.elementStyle.outlineColor = color
            if box.elementStyle.outlineWidth < 0.5 {
                box.elementStyle.outlineWidth = 2
            }
        case .boxPrimary:
            box.fillColor = color
            if box.backgroundStyle == .transparent {
                box.backgroundStyle = .solid
            }
            box.applyBackgroundStyle()
        case .boxSecondary:
            box.fillSecondaryColor = color
            box.backgroundStyle = .gradient
            box.fillOpacity = 1.0
            box.applyBackgroundStyle()
        }
        markupStyleDidChange()
        if isTextSubsheetOpen {
            let reopen = colorPickTarget
            closeTextSubsheet()
            switch reopen {
            case .text, .textGradientEnd, .textOutline: openTextColorSubsheet()
            case .boxPrimary, .boxSecondary: openBoxBackgroundSubsheet()
            }
        }
    }

    // MARK: Lifecycle

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        attachToolPickerIfNeeded()
        interactionMode = .idle
        updateModeButtonChrome()
        syncDrawingToolsVisibility()
        elevateMarkupChrome()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if toolPicker == nil { attachToolPickerIfNeeded() }
        textBoxes.forEach { constrainTextBox($0) }
        let showPencil = interactionMode == .draw && !isTextCustomizePanelVisible && !isEditingText
        bottomDockBottomConstraint?.constant = showPencil ? -pencilToolbarClearance : 0
        elevateMarkupChrome()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if let picker = toolPicker {
            picker.setVisible(false, forFirstResponder: canvas)
            picker.removeObserver(canvas)
        }
        toolPicker = nil
    }

    private func attachToolPickerIfNeeded() {
        guard toolPicker == nil else { return }
        let picker = PKToolPicker()
        toolPicker = picker
        picker.addObserver(canvas)
    }

    private var hasInk: Bool { !canvas.drawing.strokes.isEmpty }
    private var hasText: Bool { textBoxes.contains(where: \.hasText) }
    private var hasUnsavedWork: Bool { hasInk || hasText }

    @objc private func cancelTapped() {
        guard hasUnsavedWork else {
            coordinator.onDiscard()
            return
        }
        let alert = UIAlertController(
            title: "Discard markup?",
            message: "Your drawing and text will be lost unless you tap Save (checkmark).",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Keep editing", style: .cancel))
        alert.addAction(UIAlertAction(title: "Discard", style: .destructive) { [weak self] _ in
            self?.coordinator.onDiscard()
        })
        present(alert, animated: true)
    }

    @objc private func flipImageTapped() {
        let wouldClear = hasInk || hasText
        if wouldClear {
            let alert = UIAlertController(
                title: "Flip image?",
                message: "Flipping clears drawing and text so the photo lines up with a fresh canvas.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Flip & clear", style: .destructive) { [weak self] _ in
                self?.performFlipClearingMarkup()
            })
            present(alert, animated: true)
        } else {
            performFlipClearingMarkup()
        }
    }

    private func performFlipClearingMarkup() {
        baseImage = flipImageHorizontally(baseImage)
        imageView.image = baseImage
        canvas.drawing = PKDrawing()
        textBoxes.forEach { $0.removeFromSuperview() }
        textBoxes.removeAll()
        selectedTextBox = nil
    }

    @objc private func saveTapped() {
        view.endEditing(true)
        let targetSize = baseImage.size
        let mergeScale = max(1, baseImage.scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = mergeScale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let merged = renderer.image { ctx in
            let gtx = ctx.cgContext
            baseImage.draw(in: CGRect(origin: .zero, size: targetSize))
            let stroke = canvas.drawing.image(from: canvas.bounds, scale: mergeScale)
            let r = aspectFitRect(imageSize: stroke.size, in: CGRect(origin: .zero, size: targetSize))
            stroke.draw(in: r, blendMode: .normal, alpha: 1)

            let fittedInView = aspectFitRect(imageSize: baseImage.size, in: imageView.bounds)
            let sx = targetSize.width / fittedInView.width
            let sy = targetSize.height / fittedInView.height

            for box in textBoxes where box.hasText && box.exportAttributedText.length > 0 {
                let tvFrameInImageView = box.convert(box.bounds, to: imageView)
                let inter = tvFrameInImageView.intersection(fittedInView)
                guard inter.width > 4, inter.height > 4 else { continue }

                let drawRect = CGRect(
                    x: (inter.minX - fittedInView.minX) * sx,
                    y: (inter.minY - fittedInView.minY) * sy,
                    width: inter.width * sx,
                    height: inter.height * sy
                )

                if box.backgroundStyle != .transparent {
                    let padX = (box.contentPadding.left + box.contentPadding.right + box.marginHorizontal * 2) * sx
                    let padY = (box.contentPadding.top + box.contentPadding.bottom) * sy
                    let plateRect = drawRect.insetBy(dx: -(padX * 0.5 + 2 * sx), dy: -(padY * 0.5 + 2 * sy))
                    gtx.saveGState()
                    gtx.setAlpha(box.fillOpacity)
                    switch box.backgroundStyle {
                    case .transparent:
                        break
                    case .solid:
                        gtx.setFillColor(box.fillColor.cgColor)
                        gtx.fill(plateRect)
                    case .gradient:
                        let colors = [box.fillColor.cgColor, box.fillSecondaryColor.cgColor] as CFArray
                        let locs: [CGFloat] = [0, 1]
                        if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locs) {
                            gtx.drawLinearGradient(grad, start: plateRect.origin, end: CGPoint(x: plateRect.maxX, y: plateRect.maxY), options: [])
                        }
                    case .glass:
                        gtx.setFillColor(UIColor.black.withAlphaComponent(0.35).cgColor)
                        gtx.fill(plateRect)
                    }
                    gtx.restoreGState()
                }

                let scaledAttr = Self.scaledAttributedString(box.exportAttributedText, sx: sx, sy: sy)
                let shadowBlur = max(1.5, (box.baseFontSize * sx) * 0.11)
                gtx.saveGState()
                gtx.setShadow(
                    offset: CGSize(width: 0, height: max(1, (box.baseFontSize * sx) * 0.05)),
                    blur: shadowBlur,
                    color: UIColor.black.withAlphaComponent(0.62).cgColor
                )
                scaledAttr.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                gtx.restoreGState()
            }
        }
        DispatchQueue.main.async { [weak self] in
            self?.coordinator.onSave(merged)
        }
    }

    private static func scaledAttributedString(_ source: NSAttributedString, sx: CGFloat, sy: CGFloat) -> NSAttributedString {
        let m = NSMutableAttributedString(attributedString: source)
        let sScale = (sx + sy) / 2
        m.enumerateAttributes(in: NSRange(location: 0, length: m.length)) { attrs, range, _ in
            var next = attrs
            if let f = attrs[.font] as? UIFont {
                let desc = f.fontDescriptor.withSymbolicTraits(f.fontDescriptor.symbolicTraits) ?? f.fontDescriptor
                next[.font] = UIFont(descriptor: desc, size: f.pointSize * sScale)
            }
            if let ps = attrs[.paragraphStyle] as? NSParagraphStyle, let mutable = ps.mutableCopy() as? NSMutableParagraphStyle {
                mutable.lineSpacing *= sScale
                next[.paragraphStyle] = mutable
            }
            if let stroke = attrs[.strokeWidth] as? NSNumber {
                next[.strokeWidth] = stroke.doubleValue * Double(sScale)
            }
            m.setAttributes(next, range: range)
        }
        return m
    }
}

extension MarkupViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let point = touch.location(in: overlayHost)
        return !textBoxes.contains { $0.frame.contains(point) }
    }
}

