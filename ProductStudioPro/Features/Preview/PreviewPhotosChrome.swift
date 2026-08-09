import SwiftUI

// MARK: - Photos-style filmstrip & bottom actions

struct PhotosFilmstripView: View {
    let products: [CapturedProduct]
    @Binding var selectedIndex: Int
    let thumbnail: (CapturedProduct) -> UIImage
    var onSelect: ((Int) -> Void)?

    private let thumbSize = CGSize(width: 58, height: 58)

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.tight) {
                    ForEach(Array(products.enumerated()), id: \.element.id) { index, product in
                        Button {
                            onSelect?(index)
                        } label: {
                            filmstripCell(product: product, index: index)
                        }
                        .buttonStyle(FeedbackPressButtonStyle(pressedScale: 0.92))
                        .id(index)
                    }
                }
                .padding(.horizontal, DS.Space.cardPadding)
                .padding(.vertical, DS.Space.tight)
            }
            .onAppear { scrollToSelected(proxy, animated: false) }
            .onChange(of: selectedIndex) { _, _ in scrollToSelected(proxy, animated: true) }
            .onChange(of: products.count) { _, _ in scrollToSelected(proxy, animated: false) }
        }
        .frame(height: 74)
    }

    private func filmstripCell(product: CapturedProduct, index: Int) -> some View {
        let selected = index == selectedIndex
        return Image(uiImage: thumbnail(product))
            .resizable()
            .scaledToFill()
            .frame(width: thumbSize.width, height: thumbSize.height)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.thumbnail, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.thumbnail, style: .continuous)
                    .strokeBorder(
                        selected ? DS.ColorToken.accent : DS.ColorToken.separator,
                        lineWidth: selected ? 2.5 : 1
                    )
            )
            .shadow(color: DS.ColorToken.label.opacity(selected ? 0.28 : 0.10), radius: selected ? 4 : 1, y: 1)
            .opacity(selected ? 1 : 0.78)
            .scaleEffect(selected ? 1.05 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: selectedIndex)
    }

    private func scrollToSelected(_ proxy: ScrollViewProxy, animated: Bool) {
        guard selectedIndex >= 0, selectedIndex < products.count else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.22)) {
                proxy.scrollTo(selectedIndex, anchor: .center)
            }
        } else {
            proxy.scrollTo(selectedIndex, anchor: .center)
        }
    }
}

/// Bottom toolbar matching Apple Photos: icon row inside preview dock card.
struct PhotosLibraryActionBar: View {
    let onShare: () -> Void
    let onEnhance: () -> Void
    let onEdit: () -> Void
    let onBackground: () -> Void
    let onMarkup: () -> Void
    let onInfo: () -> Void
    let onDelete: () -> Void
    var polishEnabled: Bool = false
    var isEnhanceProcessing: Bool = false
    var deleteEnabled: Bool = true

    private var enhanceLabel: String {
        if isEnhanceProcessing { return "Enhance…" }
        return polishEnabled ? "Enhanced" : "Enhance"
    }

    var body: some View {
        HStack(spacing: 0) {
            FeedbackDockButton(systemName: "square.and.arrow.up", label: "Share", action: onShare)
            FeedbackDockButton(
                systemName: "sparkles",
                label: enhanceLabel,
                isEnabled: !isEnhanceProcessing,
                action: onEnhance
            )
            FeedbackDockButton(systemName: "slider.horizontal.3", label: "Edit", action: onEdit)
            FeedbackDockButton(systemName: "paintpalette.fill", label: "Background", action: onBackground)
            FeedbackDockButton(systemName: "pencil.tip.crop.circle", label: "Markup", action: onMarkup)
            FeedbackDockButton(systemName: "info.circle", label: "Info", action: onInfo)
            FeedbackDockButton(
                systemName: "trash",
                label: "Delete",
                isEnabled: deleteEnabled,
                isDestructive: true,
                action: onDelete
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DS.Space.tight)
        .padding(.top, 2)
        .padding(.bottom, DS.Space.tight)
    }
}
