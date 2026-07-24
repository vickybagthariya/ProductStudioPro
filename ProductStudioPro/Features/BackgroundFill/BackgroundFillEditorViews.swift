import SwiftUI

/// Scrollable preset-group picker — opens scrolled to the active group (system `Menu` always starts at top).
private struct GradientPresetGroupPickerSheet: View {
    @Binding var selectedGroupID: String
    var onSelect: (GradientPresetGroup) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    ForEach(GradientPresetGroupLibrary.all) { group in
                        Button {
                            InteractionHaptics.tap()
                            onSelect(group)
                            dismiss()
                        } label: {
                            HStack {
                                Text(group.title)
                                    .foregroundStyle(DS.ColorToken.label)
                                Spacer(minLength: 8)
                                if group.id == selectedGroupID {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(DS.ColorToken.accent)
                                }
                            }
                        }
                        .id(group.id)
                    }
                }
                .listStyle(.plain)
                .task { await scrollToSelectedGroup(proxy) }
            }
            .navigationTitle("Gradient presets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(DS.ColorToken.accent)
                }
                .dsHideToolbarSharedBackground()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func scrollToSelectedGroup(_ proxy: ScrollViewProxy) async {
        try? await Task.sleep(nanoseconds: 80_000_000)
        guard GradientPresetGroupLibrary.group(id: selectedGroupID) != nil else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(selectedGroupID, anchor: .center)
        }
    }
}

/// Compact liquid-glass processing card shown on the Format Background sheet while matching colors.
struct FormatBackgroundMatchingOverlay: View {
    @State private var spin = false

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(DS.ColorToken.accent.opacity(0.45), lineWidth: 5)
                    .frame(width: 64, height: 64)
                Image(systemName: "paintpalette")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(DS.ColorToken.accent)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 1.1).repeatForever(autoreverses: false), value: spin)
            }
            Text("Matching product colors…")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DS.ColorToken.label)
            Text("Sampling colors from the product for solid or gradient fill.")
                .font(DS.TypeScale.caption)
                .foregroundStyle(DS.ColorToken.secondaryLabel)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            ProgressView()
                .controlSize(.regular)
                .tint(DS.ColorToken.accent)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(maxWidth: 300)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(AppTheme.glassTint)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .stroke(AppTheme.goldBorderGlow, lineWidth: 1)
        )
        .shadow(color: AppTheme.ambientShadow, radius: 14, x: 0, y: 8)
        .onAppear { spin = true }
    }
}

/// PowerPoint-style Format Background panel (fill, preset gradients, type, direction, stops).
struct PowerPointBackgroundFillEditor: View {
    @Binding var spec: BackgroundFillSpec
    @Binding var selectedScenePresetID: String?
    /// Debounced live preview while dragging sliders / color picker.
    var onLiveSpecChange: () -> Void
    /// Committed change (end of drag, discrete control).
    var onSpecChange: () -> Void
    var onCaptureUndo: () -> Void

    @Binding var selectedGradientGroupID: String
    /// Parent bumps when Format Background sheet opens so the preset strip re-scrolls to selection.
    var presetScrollRequestID: UUID = UUID()
    var matchProductColorsEnabled: Bool = false
    var isMatchingProductColors: Bool = false
    var matchProductColorsFailureMessage: String?
    var onMatchProductColors: (() -> Void)?

    @Binding var showImageBackgroundSheet: Bool
    @Binding var showImageBackgroundVisualEditor: Bool
    @Binding var selectedImageCategory: ImageBackgroundCategory
    var imagePresetScrollRequestID: UUID = UUID()
    var canvasWidth: Int = 1200
    var canvasHeight: Int = 1200
    var fillRatio: Double = 0.88
    var cutoutSize: CGSize = CGSize(width: 1, height: 1)
    var cutoutImage: UIImage?

    @State private var selectedStopID: UUID?
    @State private var showGradientGroupPicker = false
    @State private var formatTab: FormatBackgroundTab = .color
    @State private var imagePickerBrowseTab: ImageBackgroundBrowseTab = .library

    /// Assign the full spec so parent `@State` always receives gradient type / stops changes.
    private func replaceSpec(_ next: BackgroundFillSpec, live: Bool = false, commit: Bool = false) {
        spec = next
        if commit { onSpecChange() }
        else if live { onLiveSpecChange() }
    }

    private func mutateSpec(live: Bool = false, commit: Bool = false, _ edit: (inout BackgroundFillSpec) -> Void) {
        var next = spec
        edit(&next)
        replaceSpec(next, live: live, commit: commit)
    }

    var body: some View {
        DSCard(padding: DS.Space.cardPadding) {
            VStack(alignment: .leading, spacing: DS.Space.tight) {
                headerRow
                formatTabSection

                if matchProductColorsEnabled, formatTab == .color || formatTab == .gradient {
                    matchProductColorsSection
                }

                switch formatTab {
                case .color:
                    solidColorSection
                case .gradient:
                    gradientTypeDirectionRow
                    gradientPresetGroupsSection
                    angleSection
                case .scene, .online:
                    imageSummarySection
                    if formatTab == .scene {
                        imageQuickAccessSection
                    }
                    imageEditorSection
                    shadowSection
                }
            }
        }
        .onAppear {
            formatTab = FormatBackgroundTab.resolved(from: spec)
        }
        .onChange(of: spec.fillKind) { _, kind in
            // Keep tab aligned when parent resets / applies presets externally.
            if formatTab.fillKind != kind {
                formatTab = FormatBackgroundTab.resolved(from: spec, prefersOnline: formatTab == .online)
            }
        }
        .sheet(isPresented: $showImageBackgroundSheet) {
            ImageBackgroundPickerSheet(
                spec: $spec,
                selectedCategory: $selectedImageCategory,
                presetScrollRequestID: imagePresetScrollRequestID,
                canvasWidth: canvasWidth,
                canvasHeight: canvasHeight,
                fillRatio: fillRatio,
                cutoutSize: cutoutSize,
                onCaptureUndo: onCaptureUndo,
                onLiveSpecChange: onLiveSpecChange,
                onSpecChange: onSpecChange,
                onDismiss: {},
                initialBrowseTab: imagePickerBrowseTab
            )
        }
        .fullScreenCover(isPresented: $showImageBackgroundVisualEditor) {
            if let cutoutImage {
                ImageBackgroundVisualEditorSheet(
                    initialSelection: spec.imageSelection ?? .defaultSelection(),
                    cutoutImage: cutoutImage,
                    cutoutSize: cutoutSize,
                    canvasWidth: canvasWidth,
                    canvasHeight: canvasHeight,
                    fillRatio: fillRatio,
                    onSave: { selection in
                        mutateSpec(commit: true) { s in
                            s.fillKind = .image
                            s.imageSelection = selection
                            s.normalizeImageSelection()
                        }
                    },
                    onCancel: {}
                )
                .interactiveDismissDisabled(true)
            }
        }
    }

    private var headerRow: some View {
        HStack {
            Spacer()
            Button("Reset Background") {
                onCaptureUndo()
                spec = .catalogWhite
                selectedScenePresetID = nil
                selectedStopID = spec.gradientStops.first?.id
                onSpecChange()
            }
            .font(DS.TypeScale.caption.weight(.semibold))
            .foregroundStyle(spec.fillKind == .solid && (spec.gradientStops.first?.colorHex.uppercased() == "#FFFFFF")
                ? DS.ColorToken.tertiaryLabel
                : DS.ColorToken.label)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(DS.ColorToken.backgroundTertiary, in: Capsule())
            .overlay(Capsule().stroke(DS.ColorToken.separator, lineWidth: 1))
            .disabled(spec.fillKind == .solid && (spec.gradientStops.first?.colorHex.uppercased() == "#FFFFFF"))
            .opacity(spec.fillKind == .solid && (spec.gradientStops.first?.colorHex.uppercased() == "#FFFFFF")
                ? DS.Motion.disabledOpacity
                : 1)
        }
    }

    // MARK: Fill tabs (Color / Gradient / Scene / Online)

    private var formatTabSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Background")
            HStack(spacing: 6) {
                ForEach(FormatBackgroundTab.allCases) { tab in
                    DSFillKindChoice(
                        title: tab.rawValue,
                        isSelected: formatTab == tab
                    ) {
                        selectFormatTab(tab)
                    }
                }
            }
        }
    }

    private func selectFormatTab(_ tab: FormatBackgroundTab) {
        guard formatTab != tab else {
            if tab == .scene || tab == .online {
                openImagePicker(for: tab)
            }
            return
        }
        onCaptureUndo()
        formatTab = tab
        let kind = tab.fillKind
        mutateSpec(commit: true) { s in
            s.fillKind = kind
            switch tab {
            case .color:
                s.overlay = .none
                s.imageSelection = nil
                s.gradientStops = [GradientColorStop(colorHex: s.gradientStops.first?.colorHex ?? "#FFFFFF", position: 0)]
            case .gradient:
                s.imageSelection = nil
                if s.gradientStops.count < 2 {
                    let a = s.gradientStops.first?.colorHex ?? "#FFFFFF"
                    s.gradientStops = GradientColorStop.evenDistribution(hexes: [a, "#E8E8E8"])
                }
            case .scene, .online:
                if s.imageSelection == nil {
                    s.imageSelection = .defaultSelection()
                }
                s.normalizeImageSelection()
                selectedImageCategory = ImageBackgroundFolderCatalog.category(
                    forBackgroundID: s.imageSelection?.backgroundID ?? ImageBackgroundFolderCatalog.defaultBackgroundID
                )
            }
            s.normalizeStops()
        }
        selectedStopID = spec.gradientStops.first?.id
        if tab == .scene || tab == .online {
            openImagePicker(for: tab)
        }
    }

    private func openImagePicker(for tab: FormatBackgroundTab) {
        imagePickerBrowseTab = (tab == .online) ? .online : .library
        DispatchQueue.main.async {
            showImageBackgroundSheet = true
        }
    }

    // MARK: Image fill

    private var selectedImageBackgroundTitle: String {
        guard let selection = spec.imageSelection else { return "None" }
        if let customRef = selection.customImageRef,
           let record = ImageBackgroundStore.shared.record(id: customRef) {
            return record.title
        }
        return ImageBackgroundFolderCatalog.definition(id: selection.backgroundID)?.title ?? "Background"
    }

    private var selectedImageAttribution: String? {
        guard let ref = spec.imageSelection?.customImageRef,
              let record = ImageBackgroundStore.shared.record(id: ref) else { return nil }
        return record.provenance?.attributionLine
    }

    private var imageSummarySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                sectionLabel("Background")
                Spacer()
                Button("Browse") {
                    if let id = spec.imageSelection?.backgroundID {
                        selectedImageCategory = ImageBackgroundFolderCatalog.category(forBackgroundID: id)
                    }
                    openImagePicker(for: formatTab == .online ? .online : .scene)
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.ColorToken.accent)
            }
            Text(selectedImageBackgroundTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.ColorToken.label)
            if let selectedImageAttribution {
                Text(selectedImageAttribution)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.ColorToken.secondaryLabel)
            }
        }
    }

    private var imageEditorSection: some View {
        Button {
            onCaptureUndo()
            showImageBackgroundVisualEditor = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "slider.horizontal.below.square.and.square.filled")
                    .font(.system(size: 16, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Edit Background")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Move, crop, blur, layers")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.ColorToken.secondaryLabel)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.ColorToken.secondaryLabel)
            }
            .foregroundStyle(DS.ColorToken.label)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(DS.ColorToken.backgroundTertiary, in: RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous).stroke(DS.ColorToken.separator, lineWidth: 1))
        }
        .buttonStyle(.plainPressable)
    }

    private var imageQuickAccessSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            quickBackgroundRow(title: "Recently Used", items: recentBackgroundItems)
            quickBackgroundRow(title: "Favorites", items: favoriteBackgroundItems)
        }
    }

    private var recentBackgroundItems: [ImageBackgroundListItem] {
        Array(ImageBackgroundFolderCatalog.listItems(for: ImageBackgroundRecentStore.ids).prefix(8))
    }

    private var favoriteBackgroundItems: [ImageBackgroundListItem] {
        Array(ImageBackgroundFolderCatalog.listItems(for: ImageBackgroundFavoritesStore.favoriteIDs).prefix(8))
    }

    private func quickBackgroundRow(title: String, items: [ImageBackgroundListItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel(title)
            if items.isEmpty {
                Text(title == "Favorites" ? "Star backgrounds in the picker." : "Pick a background to see it here.")
                    .font(DS.TypeScale.micro)
                    .foregroundStyle(DS.ColorToken.secondaryLabel)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(items) { item in
                            quickBackgroundThumb(item)
                        }
                    }
                }
            }
        }
    }

    private func quickBackgroundThumb(_ item: ImageBackgroundListItem) -> some View {
        let selected = spec.imageSelection?.backgroundID == item.selectionBackgroundID
            && spec.imageSelection?.customImageRef == item.customRef
        return Button {
            onCaptureUndo()
            let canvasSize = CGSize(width: CGFloat(max(canvasWidth, 1)), height: CGFloat(max(canvasHeight, 1)))
            mutateSpec(commit: true) { s in
                s.fillKind = .image
                var selection = ImageBackgroundSelection(
                    backgroundID: item.selectionBackgroundID,
                    customImageRef: item.customRef,
                    shadow: s.imageSelection?.shadow ?? .off
                )
                ImageBackgroundAutoPlacement.applyAutoPlacement(
                    to: &selection,
                    definition: item.definition,
                    cutoutSize: cutoutSize,
                    canvasSize: canvasSize,
                    fillRatio: item.isOnlineBackground
                        ? ImageBackgroundAutoPlacement.onlineBackgroundFillRatio
                        : fillRatio
                )
                s.imageSelection = selection
                s.normalizeImageSelection()
            }
            ImageBackgroundRecentStore.markUsed(item.selectionBackgroundID)
            if let ref = item.customRef {
                ImageBackgroundStore.shared.markRecentlyUsed(ref)
            }
        } label: {
            VStack(spacing: 4) {
                Image(uiImage: item.thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 64, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(selected ? DS.ColorToken.accent : DS.ColorToken.separator, lineWidth: selected ? 2 : 1)
                    )
                Text(item.title)
                    .font(.system(size: 8, weight: .semibold))
                    .lineLimit(1)
                    .frame(width: 64)
            }
        }
        .buttonStyle(.plainPressable)
    }

    private var shadowSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Shadow")
            HStack(spacing: 6) {
                ForEach(ContactShadowStrength.allCases) { strength in
                    DSFillKindChoice(
                        title: strength.rawValue,
                        isSelected: spec.imageSelection?.shadow == strength
                    ) {
                        guard spec.imageSelection?.shadow != strength else { return }
                        onCaptureUndo()
                        mutateSpec(commit: true) { s in
                            if s.imageSelection == nil {
                                s.imageSelection = .defaultSelection()
                            }
                            s.imageSelection?.shadow = strength
                        }
                    }
                }
            }
        }
    }

    private func placementSliderRow(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        display: @escaping (Double) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(DS.TypeScale.dockSection)
                    .foregroundStyle(DS.ColorToken.secondaryLabel)
                Spacer()
                Text(display(value.wrappedValue))
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(DS.ColorToken.label)
            }
            Slider(value: value, in: range)
                .tint(DS.ColorToken.accent)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(DS.ColorToken.backgroundTertiary, in: RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous).stroke(DS.ColorToken.separator, lineWidth: 1))
    }

    private var matchProductColorsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                onMatchProductColors?()
            } label: {
                HStack(spacing: 10) {
                    // Matching busy UI is InteractionHUD (above sheets) — keep this button quiet.
                    Image(systemName: "paintpalette")
                        .font(.system(size: 15, weight: .semibold))
                        .opacity(isMatchingProductColors ? DS.Motion.disabledOpacity : 1)
                    Text(isMatchingProductColors ? "Matching…" : "Match product colors")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 40)
            }
            .buttonStyle(GlassPreviewButtonStyle())
            .disabled(isMatchingProductColors || onMatchProductColors == nil)
            .animation(.easeInOut(duration: 0.2), value: isMatchingProductColors)

            if let matchProductColorsFailureMessage, !matchProductColorsFailureMessage.isEmpty {
                Text(matchProductColorsFailureMessage)
                    .font(DS.TypeScale.micro)
                    .foregroundStyle(DS.ColorToken.secondaryLabel)
            }
        }
    }

    // MARK: Grouped gradient presets (single dropdown + horizontal cards)

    private var activeGradientGroup: GradientPresetGroup {
        GradientPresetGroupLibrary.group(id: selectedGradientGroupID) ?? GradientPresetGroupLibrary.all[0]
    }

    /// Index of the active preset within the currently displayed group (drives scroll + highlight).
    private var selectedPresetIndex: Int? {
        guard let id = selectedScenePresetID else { return nil }
        return activeGradientGroup.presets.firstIndex(where: { $0.id == id })
    }

    private var selectedPresetAccessibilityLabel: String {
        guard let index = selectedPresetIndex else {
            return "No preset selected in \(activeGradientGroup.title)"
        }
        return "Preset \(index + 1) of \(activeGradientGroup.presets.count) in \(activeGradientGroup.title)"
    }

    private func presetScrollItemID(presetID: String, index: Int) -> String {
        "\(selectedGradientGroupID)-\(index)-\(presetID)"
    }

    /// User browses another preset group without forcing the group back to the committed preset.
    private func selectGradientGroup(_ group: GradientPresetGroup) {
        guard selectedGradientGroupID != group.id else { return }
        selectedGradientGroupID = group.id
    }

    private var gradientPresetGroupsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Gradient presets")
                    .font(DS.TypeScale.dockSection)
                    .foregroundStyle(DS.ColorToken.label)
                Spacer(minLength: 8)
                Button {
                    syncGradientGroupToSelectedPreset()
                    showGradientGroupPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Text(activeGradientGroup.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DS.ColorToken.label)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DS.ColorToken.secondaryLabel)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(DS.ColorToken.backgroundTertiary, in: Capsule())
                    .overlay(Capsule().stroke(DS.ColorToken.separator, lineWidth: 1))
                }
                .buttonStyle(.plainPressable)
                .accessibilityLabel("Gradient preset group, \(activeGradientGroup.title)")
                .sheet(isPresented: $showGradientGroupPicker) {
                    GradientPresetGroupPickerSheet(
                        selectedGroupID: $selectedGradientGroupID,
                        onSelect: { selectGradientGroup($0) }
                    )
                }
            }

            if let selectedTitle = selectedScenePresetTitle {
                Text("Selected: \(selectedTitle)")
                    .font(DS.TypeScale.micro)
                    .foregroundStyle(DS.ColorToken.accent)
            }

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(activeGradientGroup.presets.enumerated()), id: \.element.id) { index, preset in
                            scenePresetThumb(preset, index: index)
                                .id(presetScrollItemID(presetID: preset.id, index: index))
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .id("gradient-preset-strip-\(selectedGradientGroupID)")
                .onAppear {
                    requestScrollToSelectedPreset(proxy, animated: false, alignGroupToSelection: true)
                }
                .onChange(of: selectedScenePresetID) { _, _ in
                    requestScrollToSelectedPreset(proxy, animated: true, alignGroupToSelection: false)
                }
                .onChange(of: selectedGradientGroupID) { _, _ in
                    requestScrollToSelectedPreset(proxy, animated: false, alignGroupToSelection: false)
                }
                .onChange(of: selectedPresetIndex) { _, _ in
                    requestScrollToSelectedPreset(proxy, animated: false, alignGroupToSelection: false)
                }
                .onChange(of: presetScrollRequestID) { _, _ in
                    requestScrollToSelectedPreset(proxy, animated: false, alignGroupToSelection: true)
                }
            }
            .accessibilityValue(selectedPresetAccessibilityLabel)
        }
        .padding(8)
        .background(DS.ColorToken.backgroundTertiary.opacity(0.55), in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                .stroke(DS.ColorToken.separator, lineWidth: 1)
        )
    }

    private var selectedScenePresetTitle: String? {
        guard let id = selectedScenePresetID else { return nil }
        for group in GradientPresetGroupLibrary.all {
            if let p = group.presets.first(where: { $0.id == id }) { return p.title }
        }
        return BackgroundScenePresetLibrary.all.first { $0.id == id }?.title
    }

    private func applyScenePreset(_ preset: BackgroundScenePreset) {
        onCaptureUndo()
        spec = preset.spec
        selectedScenePresetID = preset.id
        if let group = GradientPresetGroupLibrary.groupContainingPreset(id: preset.id) {
            selectedGradientGroupID = group.id
        }
        selectedStopID = spec.gradientStops.first?.id
        onSpecChange()
    }

    private func syncGradientGroupToSelectedPreset() {
        guard let presetID = selectedScenePresetID,
              let group = GradientPresetGroupLibrary.groupContainingPreset(id: presetID) else { return }
        selectedGradientGroupID = group.id
    }

    /// Keeps the horizontal preset list anchored on the active selection so reopening the panel
    /// scrolls straight to (and highlights) the currently chosen gradient template.
    /// - Parameter alignGroupToSelection: When true (sheet open / first appear), snap the group dropdown
    ///   to the preset's library group. When false, respect the user's manually chosen group.
    private func requestScrollToSelectedPreset(
        _ proxy: ScrollViewProxy,
        animated: Bool,
        alignGroupToSelection: Bool
    ) {
        if alignGroupToSelection {
            syncGradientGroupToSelectedPreset()
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 90_000_000)
            guard !Task.isCancelled else { return }
            scrollToSelectedPreset(proxy, animated: animated)
        }
    }

    private func scrollToSelectedPreset(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let index = selectedPresetIndex else { return }
        let presets = activeGradientGroup.presets
        guard presets.indices.contains(index) else { return }
        let scrollID = presetScrollItemID(presetID: presets[index].id, index: index)
        if animated {
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(scrollID, anchor: .center)
            }
        } else {
            proxy.scrollTo(scrollID, anchor: .center)
        }
    }

    private func scenePresetThumb(_ preset: BackgroundScenePreset, index: Int) -> some View {
        let selected = selectedPresetIndex == index && selectedScenePresetID == preset.id
        return Button {
            applyScenePreset(preset)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(preset.title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(selected ? DS.ColorToken.accent : DS.ColorToken.label)
                    .lineLimit(1)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(BackgroundFillPreview.shape(spec: preset.spec))
                    .frame(width: 72, height: 40)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(selected ? DS.ColorToken.accent : DS.ColorToken.separator, lineWidth: selected ? 2.5 : 1)
                    )
            }
            .padding(6)
            .background(selected ? DS.ColorToken.accent.opacity(0.12) : DS.ColorToken.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.compactControl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.compactControl, style: .continuous)
                    .stroke(selected ? DS.ColorToken.accent.opacity(0.55) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plainPressable)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Type / direction / angle

    private var gradientTypeBinding: Binding<GradientFillType> {
        Binding(
            get: { spec.gradientType },
            set: { newType in
                let oldType = spec.gradientType
                guard oldType != newType else { return }
                onCaptureUndo()
                selectedScenePresetID = nil
                mutateSpec(commit: true) { s in
                    s.gradientType = newType
                    if s.overlay != .blackWhite { s.overlay = .none }
                    if newType == .radial || newType == .mesh {
                        s.gradientDirection = .center
                    } else if s.gradientDirection == .center {
                        s.gradientDirection = .bottomTrailing
                        s.gradientAngleDegrees = 135
                    } else if newType.supportsAngle, !oldType.supportsAngle {
                        s.gradientAngleDegrees = s.gradientDirection.defaultAngleDegrees
                    } else if newType.supportsDirection, !newType.supportsAngle {
                        s.gradientAngleDegrees = s.gradientDirection.defaultAngleDegrees
                    }
                    s.normalizeStops()
                }
            }
        )
    }

    private var gradientDirectionBinding: Binding<GradientFillDirection> {
        Binding(
            get: { spec.gradientDirection },
            set: { newDir in
                let oldDir = spec.gradientDirection
                guard oldDir != newDir, spec.gradientType.supportsDirection else { return }
                onCaptureUndo()
                selectedScenePresetID = nil
                mutateSpec(commit: true) { s in
                    s.gradientDirection = newDir
                    if s.gradientType.supportsAngle {
                        s.gradientAngleDegrees = newDir.defaultAngleDegrees
                    }
                }
            }
        )
    }

    private var gradientAngleBinding: Binding<Double> {
        Binding(
            get: { spec.gradientAngleDegrees },
            set: { newAngle in
                guard spec.gradientAngleDegrees != newAngle else { return }
                selectedScenePresetID = nil
                mutateSpec(live: true) { $0.gradientAngleDegrees = newAngle }
            }
        )
    }

    private var gradientTypeDirectionRow: some View {
        HStack(alignment: .top, spacing: 8) {
            DSFormMenuPicker(
                title: "Type",
                valueTitle: spec.gradientType.rawValue,
                selection: gradientTypeBinding,
                options: GradientFillType.formatBackgroundPickerCases.map { ($0, $0.rawValue) }
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            DSFormMenuPicker(
                title: "Direction",
                valueTitle: spec.gradientDirection.rawValue,
                selection: gradientDirectionBinding,
                options: GradientFillDirection.formatBackgroundPickerCases.map { ($0, $0.rawValue) },
                isEnabled: spec.gradientType.supportsDirection
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .id("direction-\(spec.gradientType.rawValue)-\(spec.gradientDirection.rawValue)")
        }
    }

    @ViewBuilder
    private var angleSection: some View {
        if spec.gradientType.supportsAngle {
            HStack(spacing: 10) {
                sectionLabel("Angle")
                Spacer(minLength: 8)
                Text("\(Int(spec.gradientAngleDegrees))°")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(DS.ColorToken.label)
                Stepper("Angle", value: gradientAngleBinding, in: 0...359, step: 15)
                    .labelsHidden()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(DS.ColorToken.backgroundTertiary, in: RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                    .stroke(DS.ColorToken.separator, lineWidth: 1)
            )
        }
    }

    // MARK: Gradient stops (PPT)

    private var gradientStopsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionLabel("Gradient stops")
                Spacer()
                Button {
                    onCaptureUndo()
                    addStop()
                    onSpecChange()
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .disabled(spec.overlay == .blackWhite || spec.gradientStops.count >= 8)
                if spec.gradientStops.count > spec.minimumStopCount {
                    Button {
                        onCaptureUndo()
                        removeSelectedStop()
                        onSpecChange()
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }

            if spec.overlay == .blackWhite {
                Label("Black & White preset uses a fixed neutral ramp.", systemImage: "circle.lefthalf.filled")
                    .font(.caption)
                    .foregroundStyle(DS.ColorToken.secondaryLabel)
            } else {
                gradientStopBar
                if let stop = selectedStop {
                    selectedStopEditor(stop)
                }
            }
        }
        .onAppear { ensureSelectedStop() }
        .onChange(of: spec.gradientStops.count) { _, _ in ensureSelectedStop() }
    }

    private var selectedStop: GradientColorStop? {
        guard let id = selectedStopID else { return spec.gradientStops.first }
        return spec.gradientStops.first(where: { $0.id == id }) ?? spec.gradientStops.first
    }

    private func ensureSelectedStop() {
        if let id = selectedStopID, spec.gradientStops.contains(where: { $0.id == id }) { return }
        selectedStopID = sortedStops.first?.id
    }

    private var sortedStops: [GradientColorStop] {
        spec.gradientStops.sorted { $0.position < $1.position }
    }

    /// PPT-style bar: tap a stop to select; edit position/color in the panel below (no drag on bar).
    private var gradientStopBar: some View {
        GeometryReader { geo in
            let trackW = max(1, geo.size.width)
            let markerSize: CGFloat = 20
            ZStack(alignment: .topLeading) {
                Image(uiImage: BackgroundFillPreview.renderedImage(spec: spec, size: CGSize(width: trackW, height: 36)))
                    .resizable()
                    .scaledToFit()
                    .frame(width: trackW, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                ForEach(sortedStops) { stop in
                    let isSelected = selectedStopID == stop.id
                    let x = CGFloat(stop.position) * max(0, trackW - markerSize) + markerSize / 2
                    Button {
                        selectedStopID = stop.id
                    } label: {
                        VStack(spacing: 2) {
                            Circle()
                                .fill(Color(uiColor: stop.uiColor()))
                                .frame(width: markerSize, height: markerSize)
                                .overlay(
                                    Circle()
                                        .stroke(isSelected ? DS.ColorToken.warning : DS.ColorToken.label, lineWidth: isSelected ? 3 : 1.5)
                                )
                                .shadow(color: .black.opacity(0.35), radius: isSelected ? 3 : 1, y: 1)
                            if isSelected {
                                TrianglePointer()
                                    .fill(DS.ColorToken.warning)
                                    .frame(width: 10, height: 6)
                            }
                        }
                    }
                    .buttonStyle(.plainPressable)
                    .position(x: x, y: isSelected ? 14 : 18)
                }
            }
        }
        .frame(height: 44)
    }

    private struct TrianglePointer: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.closeSubpath()
            return p
        }
    }

    private func selectedStopEditor(_ stop: GradientColorStop) -> some View {
        let stopNum = stopSequenceNumber(for: stop)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Stop \(stopNum)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(DS.ColorToken.warning)
                Circle()
                    .fill(Color(uiColor: stop.uiColor()))
                    .frame(width: 24, height: 24)
                    .overlay(Circle().stroke(DS.ColorToken.separator, lineWidth: 1))
                ColorPicker("Color", selection: colorBinding(for: stop.id), supportsOpacity: false)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
            }

            stopPositionControl(for: stop)
            stopSlider(title: "Transparency", value: transparencyBinding(for: stop.id), range: 0...1, format: "%.0f%%", scale: 100)
            stopSlider(title: "Brightness", value: brightnessBinding(for: stop.id), range: 0...2, format: "%.0f%%", scale: 50)
        }
        .padding(12)
        .background(DS.ColorToken.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(DS.ColorToken.warning.opacity(0.55), lineWidth: 1.5))
    }

    @ViewBuilder
    private func stopPositionControl(for stop: GradientColorStop) -> some View {
        let range = positionRange(for: stop)
        if range.lowerBound >= range.upperBound {
            HStack {
                Text("Position")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.ColorToken.secondaryLabel)
                    .frame(width: 88, alignment: .leading)
                Text("\(Int(stop.position * 100))%")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(DS.ColorToken.secondaryLabel)
                Spacer()
            }
        } else {
            stopSlider(
                title: "Position",
                value: positionBinding(for: stop.id),
                range: range,
                format: "%.0f%%",
                scale: 100,
                onEditingChanged: { editing in
                    // Position edits trigger heavy background rebuild; committing at end of drag keeps UI responsive.
                    if !editing { onSpecChange() }
                }
            )
        }
    }

    private func positionRange(for stop: GradientColorStop) -> ClosedRange<Double> {
        let ordered = sortedStops
        guard let index = ordered.firstIndex(where: { $0.id == stop.id }) else { return 0...1 }
        if index == 0 { return 0...0 }
        if index == ordered.count - 1 { return 1...1 }
        let minPos = ordered[index - 1].position + 0.01
        let maxPos = ordered[index + 1].position - 0.01
        return minPos...max(maxPos, minPos + 0.02)
    }

    private func stopSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: String,
        scale: Double,
        onEditingChanged: ((Bool) -> Void)? = nil
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.ColorToken.secondaryLabel)
                .frame(width: 88, alignment: .leading)
            Slider(value: value, in: range) { editing in
                onEditingChanged?(editing)
            }
            Text(String(format: format, value.wrappedValue * scale))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(DS.ColorToken.secondaryLabel)
                .frame(width: 40, alignment: .trailing)
        }
    }

    private var solidColorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Color")
            if let first = spec.gradientStops.first {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(uiColor: first.uiColor()))
                        .frame(width: 44, height: 28)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(DS.ColorToken.separator, lineWidth: 1))
                    ColorPicker("Background color", selection: colorBinding(for: first.id), supportsOpacity: false)
                        .font(.system(size: 13, weight: .semibold))
                }
            }
        }
    }

    private func stopSequenceNumber(for stop: GradientColorStop) -> Int {
        let ordered = spec.gradientStops.sorted { $0.position < $1.position }
        return (ordered.firstIndex(where: { $0.id == stop.id }) ?? 0) + 1
    }


    // MARK: Bindings

    private func colorBinding(for id: UUID) -> Binding<Color> {
        Binding(
            get: {
                guard let stop = spec.gradientStops.first(where: { $0.id == id }) else { return .white }
                return Color(uiColor: stop.uiColor())
            },
            set: { newColor in
                let hex = UIColor(newColor).hexString
                guard spec.gradientStops.first(where: { $0.id == id })?.colorHex != hex else { return }
                selectedScenePresetID = nil
                mutateSpec(live: true) { s in
                    guard let index = s.gradientStops.firstIndex(where: { $0.id == id }) else { return }
                    s.gradientStops[index].colorHex = hex
                }
            }
        )
    }

    private func positionBinding(for id: UUID) -> Binding<Double> {
        Binding(
            get: { spec.gradientStops.first(where: { $0.id == id })?.position ?? 0 },
            set: { newValue in
                selectedScenePresetID = nil
                mutateSpec(live: true) { s in
                    guard let index = s.gradientStops.firstIndex(where: { $0.id == id }) else { return }
                    let ordered = s.gradientStops.sorted { $0.position < $1.position }
                    guard let rank = ordered.firstIndex(where: { $0.id == id }) else { return }
                    var clamped = min(1, max(0, newValue))
                    if rank == 0 {
                        clamped = 0
                    } else if rank == ordered.count - 1 {
                        clamped = 1
                    } else {
                        let lo = ordered[rank - 1].position + 0.005
                        let hi = ordered[rank + 1].position - 0.005
                        clamped = min(hi, max(lo, clamped))
                    }
                    s.gradientStops[index].position = clamped
                    s.gradientStops.sort { $0.position < $1.position }
                }
            }
        )
    }

    private func transparencyBinding(for id: UUID) -> Binding<Double> {
        Binding(
            get: { spec.gradientStops.first(where: { $0.id == id })?.transparency ?? 0 },
            set: { newValue in
                selectedScenePresetID = nil
                mutateSpec(live: true) { s in
                    guard let index = s.gradientStops.firstIndex(where: { $0.id == id }) else { return }
                    s.gradientStops[index].transparency = newValue
                }
            }
        )
    }

    private func brightnessBinding(for id: UUID) -> Binding<Double> {
        Binding(
            get: { spec.gradientStops.first(where: { $0.id == id })?.brightness ?? 1 },
            set: { newValue in
                selectedScenePresetID = nil
                mutateSpec(live: true) { s in
                    guard let index = s.gradientStops.firstIndex(where: { $0.id == id }) else { return }
                    s.gradientStops[index].brightness = newValue
                }
            }
        )
    }

    private func addStop() {
        let midColor = spec.gradientStops[spec.gradientStops.count / 2].colorHex
        let newStop = GradientColorStop(colorHex: midColor, position: 0.5)
        mutateSpec { s in
            s.gradientStops.append(newStop)
            s.normalizeStops()
        }
        selectedStopID = newStop.id
    }

    private func removeSelectedStop() {
        guard spec.gradientStops.count > spec.minimumStopCount else { return }
        mutateSpec { s in
            if let id = selectedStopID, let index = s.gradientStops.firstIndex(where: { $0.id == id }) {
                s.gradientStops.remove(at: index)
            } else {
                s.gradientStops.removeLast()
            }
            s.normalizeStops()
        }
        selectedStopID = spec.gradientStops.first?.id
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(DS.TypeScale.caption.weight(.semibold))
            .foregroundStyle(DS.ColorToken.secondaryLabel)
    }
}
