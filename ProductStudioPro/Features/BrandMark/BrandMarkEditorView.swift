import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Home / Settings destination for Brand Kit (text + logo watermark).
struct BrandMarkEditorView: View {
    @EnvironmentObject private var session: CaptureSessionStore

    @State private var showPhotoPicker = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showFileImporter = false
    @State private var logoError: String?
    @State private var previewImage: UIImage?
    @State private var markFreePreviewBase: UIImage?
    @State private var markFreeBaseProductID: UUID?
    /// True when original could not be loaded — use abstract sample instead of stamped queue image.
    @State private var markFreeBaseUnavailable = false
    @State private var previewTask: Task<Void, Never>?
    @State private var markFreeBaseTask: Task<Void, Never>?
    @State private var showFontPicker = false
    @State private var showImageNameFontPicker = false
    @State private var showCustomFontSizeAlert = false
    @State private var showImageNameCustomFontSizeAlert = false
    @State private var customFontSizeText = ""
    @State private var imageNameCustomFontSizeText = ""
    @State private var showApplyQueueConfirm = false
    @State private var expandWatermark = false
    @State private var expandText = false
    @State private var expandLogo = false
    @State private var expandImageName = false
    @State private var expandQueue = false
    @State private var expandApplying = false
    @State private var expandReset = false

    var body: some View {
        AppScreenScaffold(
            title: "Brand Kit",
            subtitle: "Live preview of your logo and text on catalog photos",
            showsHome: false,
            onBack: { session.popNavigation() },
            onHome: { session.goHome() },
            layout: .scroll
        ) {
            liveCanvasPreview

            brandKitCollapsibleSection(
                title: "Watermark",
                icon: "seal",
                isExpanded: $expandWatermark,
                summary: session.brandMarkEnabled ? "On" : "Off"
            ) {
                Toggle("Enable Brand Kit", isOn: $session.brandMarkEnabled)
                    .tint(DS.ColorToken.accent)
                DSDivider()
                DSHelperText("Off by default. Some marketplaces prefer images without watermarks.")
            }

            brandKitCollapsibleSection(
                title: "Text",
                icon: "textformat",
                isExpanded: $expandText,
                summary: textSectionSummary
            ) {
                Toggle("Show text", isOn: $session.brandMarkShowText)
                    .tint(DS.ColorToken.accent)
                    .disabled(!session.brandMarkEnabled)
                DSDivider()
                TextField("Company name", text: $session.brandMarkText)
                    .textInputAutocapitalization(.words)
                    .textFieldStyle(.roundedBorder)
                    .dsSemanticTextField()
                    .disabled(!session.brandMarkEnabled || !session.brandMarkShowText)
                    .opacity(session.brandMarkEnabled && session.brandMarkShowText ? 1 : 0.55)

                if session.businessName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                    DSDivider()
                    Button("Use “\(session.businessName)”") {
                        session.brandMarkText = session.businessName
                        session.brandMarkShowText = true
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.ColorToken.accent)
                    .disabled(!session.brandMarkEnabled)
                }

                DSDivider()
                fontControlsRow
                    .disabled(!session.brandMarkEnabled || !session.brandMarkShowText)
                    .opacity(session.brandMarkEnabled && session.brandMarkShowText ? 1 : 0.55)

                DSDivider()
                Toggle("Line wrap", isOn: $session.brandMarkTextLineWrapEnabled)
                    .tint(DS.ColorToken.accent)
                    .disabled(!session.brandMarkEnabled || !session.brandMarkShowText)
                DSHelperText("Off keeps a single truncated line. Turn on if a long name needs a second line.")
                    .opacity(session.brandMarkEnabled && session.brandMarkShowText ? 1 : 0.55)

                DSDivider()
                edgePaddingSlider(
                    title: "Edge padding",
                    value: $session.brandMarkEdgePaddingFraction,
                    enabled: session.brandMarkEnabled
                )
                DSHelperText("Default 2.5% uses the free gutter around a 95% product fill.")
                    .opacity(session.brandMarkEnabled ? 1 : 0.55)

                DSDivider()
                Toggle("Caption background", isOn: $session.brandMarkTextCaptionPlateEnabled)
                    .tint(DS.ColorToken.accent)
                    .disabled(!session.brandMarkEnabled || !session.brandMarkShowText)
                    .opacity(session.brandMarkEnabled && session.brandMarkShowText ? 1 : 0.55)

                if session.brandMarkTextCaptionPlateEnabled {
                    DSDivider()
                    colorPresetsRow
                        .disabled(!session.brandMarkEnabled || !session.brandMarkShowText)
                        .opacity(session.brandMarkEnabled && session.brandMarkShowText ? 1 : 0.55)

                    DSDivider()
                    HStack(spacing: 20) {
                        colorPickerRow(
                            title: "Text",
                            hex: Binding(
                                get: { session.brandMarkFontColorHex },
                                set: { session.brandMarkFontColorHex = $0 }
                            )
                        )
                        colorPickerRow(
                            title: "Caption",
                            hex: Binding(
                                get: { session.brandMarkCaptionPlateColorHex },
                                set: { session.brandMarkCaptionPlateColorHex = $0 }
                            )
                        )
                    }
                    .disabled(!session.brandMarkEnabled || !session.brandMarkShowText)
                    .opacity(session.brandMarkEnabled && session.brandMarkShowText ? 1 : 0.55)

                    DSDivider()
                    opacitySliderRow(
                        title: "Caption opacity",
                        value: $session.brandMarkCaptionPlateOpacity,
                        range: BrandMarkOpacityRange.plateMin...BrandMarkOpacityRange.plateMax,
                        enabled: session.brandMarkEnabled && session.brandMarkShowText
                    )
                } else {
                    DSDivider()
                    colorPickerRow(
                        title: "Font color",
                        hex: Binding(
                            get: { session.brandMarkFontColorHex },
                            set: { session.brandMarkFontColorHex = $0 }
                        )
                    )
                    .disabled(!session.brandMarkEnabled || !session.brandMarkShowText)
                    .opacity(session.brandMarkEnabled && session.brandMarkShowText ? 1 : 0.55)
                }

                DSDivider()
                Text("Position")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.ColorToken.label)
                positionGrid(
                    selected: session.brandMarkPosition,
                    blocked: session.imageNameOccupiedPosition,
                    enabled: session.brandMarkEnabled,
                    onSelect: { session.setBrandMarkPosition($0) }
                )
                .opacity(session.brandMarkEnabled ? 1 : 0.55)
                Text(session.brandMarkPosition.title)
                    .font(DS.TypeScale.bodyEmphasis)
                    .foregroundStyle(DS.ColorToken.secondaryLabel)
                DSHelperText("Cannot share a slot with Image Name. Size uses Markup points.")
            }

            brandKitCollapsibleSection(
                title: "Logo",
                icon: "photo.on.rectangle",
                isExpanded: $expandLogo,
                summary: logoSectionSummary
            ) {
                Toggle("Show logo", isOn: $session.brandMarkShowLogo)
                    .tint(DS.ColorToken.accent)
                    .disabled(!session.brandMarkEnabled)
                DSDivider()
                if let logo = BrandMarkLogoStore.loadLogo(fileName: session.brandMarkLogoFileName) {
                    HStack(spacing: 12) {
                        Image(uiImage: logo)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 56, height: 56)
                            .padding(6)
                            .background(DS.ColorToken.backgroundTertiary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(DS.ColorToken.separator, lineWidth: 1)
                            )
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Logo ready")
                                .font(.system(size: 13, weight: .semibold))
                            Button("Remove logo", role: .destructive) {
                                session.clearBrandMarkLogo()
                                schedulePreviewRefresh()
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .disabled(!session.brandMarkEnabled)
                        }
                        Spacer()
                    }
                    DSDivider()
                }
                VStack(spacing: 8) {
                    Button {
                        showPhotoPicker = true
                    } label: {
                        Label("Choose from Photos", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(!session.brandMarkEnabled)

                    Button {
                        showFileImporter = true
                    } label: {
                        Label("Choose from Files", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(!session.brandMarkEnabled)
                }
                if let logoError {
                    Text(logoError)
                        .font(DS.TypeScale.micro)
                        .foregroundStyle(.red.opacity(0.85))
                }
                DSDivider()
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Logo size")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DS.ColorToken.label)
                        Spacer()
                        Text("\(Int((session.brandMarkLogoScale * 100).rounded()))%")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DS.ColorToken.secondaryLabel)
                    }
                    Slider(
                        value: $session.brandMarkLogoScale,
                        in: BrandMarkLogoScaleRange.minimum...BrandMarkLogoScaleRange.maximum,
                        step: 0.01
                    )
                    .tint(DS.ColorToken.accent)
                    .disabled(!session.brandMarkEnabled || !session.brandMarkShowLogo)
                }
                DSDivider()
                opacitySliderRow(
                    title: "Logo opacity",
                    value: $session.brandMarkLogoOpacity,
                    range: BrandMarkOpacityRange.logoMin...BrandMarkOpacityRange.logoMax,
                    enabled: session.brandMarkEnabled && session.brandMarkShowLogo
                )
                DSHelperText("Size is % of canvas short edge (default 12%). PNG/JPG with transparency works best.")
            }

            brandKitCollapsibleSection(
                title: "Image Name",
                icon: "text.badge.checkmark",
                isExpanded: $expandImageName,
                summary: imageNameSectionSummary
            ) {
                Toggle("Show image name", isOn: $session.imageNameStampEnabled)
                    .tint(DS.ColorToken.accent)
                DSHelperText("Stamps the photo’s file / UPC name. Independent of Brand Mark text and logo.")

                if session.imageNameStampEnabled {
                    DSDivider()
                    imageNameFontControlsRow

                    DSDivider()
                    Toggle("Line wrap", isOn: $session.imageNameStampLineWrapEnabled)
                        .tint(DS.ColorToken.accent)
                    DSHelperText("Off keeps a single truncated line so long names don’t grow into Brand Mark.")

                    DSDivider()
                    edgePaddingSlider(
                        title: "Edge padding",
                        value: $session.imageNameStampEdgePaddingFraction,
                        enabled: true
                    )

                    DSDivider()
                    Toggle("Caption background", isOn: $session.imageNameStampTextCaptionPlateEnabled)
                        .tint(DS.ColorToken.accent)
                    if session.imageNameStampTextCaptionPlateEnabled {
                        DSDivider()
                        imageNameColorPresetsRow
                        DSDivider()
                        HStack(spacing: 20) {
                            colorPickerRow(
                                title: "Text",
                                hex: Binding(
                                    get: { session.imageNameStampFontColorHex },
                                    set: { session.imageNameStampFontColorHex = $0 }
                                )
                            )
                            colorPickerRow(
                                title: "Caption",
                                hex: Binding(
                                    get: { session.imageNameStampCaptionPlateColorHex },
                                    set: { session.imageNameStampCaptionPlateColorHex = $0 }
                                )
                            )
                        }
                        DSDivider()
                        opacitySliderRow(
                            title: "Caption opacity",
                            value: $session.imageNameStampCaptionPlateOpacity,
                            range: BrandMarkOpacityRange.plateMin...BrandMarkOpacityRange.plateMax,
                            enabled: true
                        )
                    } else {
                        DSDivider()
                        colorPickerRow(
                            title: "Font color",
                            hex: Binding(
                                get: { session.imageNameStampFontColorHex },
                                set: { session.imageNameStampFontColorHex = $0 }
                            )
                        )
                    }

                    DSDivider()
                    Text("Position")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.ColorToken.label)
                    positionGrid(
                        selected: session.imageNameStampPosition,
                        blocked: session.brandMarkOccupiedPosition,
                        enabled: true,
                        onSelect: { session.setImageNameStampPosition($0) }
                    )
                    Text(session.imageNameStampPosition.title)
                        .font(DS.TypeScale.bodyEmphasis)
                        .foregroundStyle(DS.ColorToken.secondaryLabel)
                    DSHelperText("Cannot share a slot with Brand Mark. Occupied cells show —.")
                }
            }

            brandKitCollapsibleSection(
                title: "Queue",
                icon: "rectangle.stack.badge.plus",
                isExpanded: $expandQueue,
                summary: canApplyBrandMarkToQueue ? "Ready" : "—"
            ) {
                Button {
                    showApplyQueueConfirm = true
                } label: {
                    Label("Apply Brand Kit to queue", systemImage: "seal")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canApplyBrandMarkToQueue)
                .opacity(canApplyBrandMarkToQueue ? 1 : 0.45)
                DSDivider()
                DSHelperText(queueApplyHelpText)
            }

            brandKitCollapsibleSection(
                title: "Reset",
                icon: "arrow.counterclockwise",
                isExpanded: $expandReset,
                summary: nil
            ) {
                Button {
                    InteractionHaptics.selection()
                    session.resetBrandKitToDefaults()
                } label: {
                    Label("Reset Brand Kit to defaults", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                DSHelperText("Restores positions, sizes, caption, padding, wrap, and colors. Keeps your company name and logo file. Apply to queue afterward if needed.")
            }

            brandKitCollapsibleSection(
                title: "Applying",
                icon: "info.circle",
                isExpanded: $expandApplying,
                summary: nil
            ) {
                DSHelperText("Brand Mark and Image Name are stamped when you capture, import, Apply, or Reprocess. Share uses that processed image. Hide Brand Kit per photo from the ⋯ menu (queue or preview), or in Edit & Polish.")
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            if session.brandMarkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !session.businessName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                session.brandMarkText = session.businessName
            }
            scheduleMarkFreeBaseRefresh()
        }
        .onDisappear {
            previewTask?.cancel()
            markFreeBaseTask?.cancel()
        }
        .onChange(of: session.brandMarkSettingsRevision) { _, _ in
            schedulePreviewRefresh()
        }
        .onChange(of: session.brandMarkFontStyle) { _, _ in
            schedulePreviewRefresh()
        }
        .onChange(of: session.brandMarkFontPostScriptName) { _, _ in
            schedulePreviewRefresh()
        }
        .onChange(of: session.brandMarkFontSizePx) { _, _ in
            schedulePreviewRefresh()
        }
        .onChange(of: session.imageNameStampFontStyle) { _, _ in
            schedulePreviewRefresh()
        }
        .onChange(of: session.brandMarkLogoRevision) { _, _ in
            schedulePreviewRefresh()
        }
        .onChange(of: session.products.first?.id) { _, _ in
            scheduleMarkFreeBaseRefresh()
        }
        .onChange(of: session.imageNamingMode) { _, _ in
            schedulePreviewRefresh()
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItems, maxSelectionCount: 1, matching: .images)
        .onChange(of: selectedPhotoItems) { _, items in
            guard let item = items.first else { return }
            Task { await importLogoFromPhotos(item) }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
            importLogoFromFiles(result)
        }
        .sheet(isPresented: $showFontPicker) {
            BrandMarkSystemFontPicker(
                postScriptName: $session.brandMarkFontPostScriptName,
                onDismiss: { showFontPicker = false }
            )
        }
        .sheet(isPresented: $showImageNameFontPicker) {
            BrandMarkSystemFontPicker(
                postScriptName: $session.imageNameStampFontPostScriptName,
                onDismiss: { showImageNameFontPicker = false }
            )
        }
        .alert("Custom font size", isPresented: $showCustomFontSizeAlert) {
            TextField("Size in pt", text: $customFontSizeText)
                .keyboardType(.numberPad)
            Button("Cancel", role: .cancel) {}
            Button("Set") { commitCustomFontSize() }
        } message: {
            Text("Enter a size from \(BrandMarkFontSizePreset.minimum) to \(BrandMarkFontSizePreset.maximum) pt.")
        }
        .alert("Custom image name size", isPresented: $showImageNameCustomFontSizeAlert) {
            TextField("Size in pt", text: $imageNameCustomFontSizeText)
                .keyboardType(.numberPad)
            Button("Cancel", role: .cancel) {}
            Button("Set") { commitImageNameCustomFontSize() }
        } message: {
            Text("Enter a size from \(BrandMarkFontSizePreset.minimum) to \(BrandMarkFontSizePreset.maximum) pt.")
        }
        .confirmationDialog(
            "Apply Brand Kit to queue?",
            isPresented: $showApplyQueueConfirm,
            titleVisibility: .visible
        ) {
            Button("Apply to \(queueApplyTargetCount) photo\(queueApplyTargetCount == 1 ? "" : "s")") {
                session.applyBrandMarkToQueue()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Restamps the current text and logo settings onto photos already in the queue. Photos marked Hide Brand Kit stay unmarked.")
        }
    }

    private var textSectionSummary: String {
        guard session.brandMarkEnabled, session.brandMarkShowText else { return "Hidden" }
        return "\(session.brandMarkFontSizePx) pt · \(session.brandMarkPosition.title)"
    }

    private var logoSectionSummary: String {
        guard session.brandMarkEnabled, session.brandMarkShowLogo else { return "Hidden" }
        return "\(Int((session.brandMarkLogoScale * 100).rounded()))%"
    }

    private var imageNameSectionSummary: String {
        guard session.imageNameStampEnabled else { return "Off" }
        return "\(session.imageNameStampFontSizePx) pt · \(session.imageNameStampPosition.title)"
    }

    private func brandKitCollapsibleSection<Content: View>(
        title: String,
        icon: String,
        isExpanded: Binding<Bool>,
        summary: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let bodyContent = content()
        return DSCard(padding: DS.Space.cardPadding + 4) {
            VStack(alignment: .leading, spacing: DS.Space.stack + 2) {
                Button {
                    InteractionHaptics.selection()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.wrappedValue.toggle()
                    }
                } label: {
                    HStack(spacing: 10) {
                        IconBadge(systemName: icon, dimension: 38, iconFontSize: 16)
                        Text(title)
                            .font(DS.TypeScale.sectionTitle)
                            .foregroundStyle(DS.ColorToken.label)
                        Spacer(minLength: 8)
                        if let summary, !summary.isEmpty, !isExpanded.wrappedValue {
                            Text(summary)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(DS.ColorToken.secondaryLabel)
                                .lineLimit(1)
                        }
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DS.ColorToken.secondaryLabel)
                            .rotationEffect(.degrees(isExpanded.wrappedValue ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded.wrappedValue {
                    VStack(alignment: .leading, spacing: DS.Space.stack) {
                        bodyContent
                    }
                }
            }
        }
        .shadow(color: DS.Shadow.card.color, radius: DS.Shadow.card.radius, x: 0, y: DS.Shadow.card.y)
    }

    private func edgePaddingSlider(
        title: String,
        value: Binding<Double>,
        enabled: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.ColorToken.label)
                Spacer()
                Text(String(format: "%.1f%%", value.wrappedValue * 100))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.ColorToken.secondaryLabel)
            }
            Slider(
                value: value,
                in: BrandMarkEdgePaddingRange.minimum...BrandMarkEdgePaddingRange.maximum,
                step: 0.005
            )
            .tint(DS.ColorToken.accent)
            .disabled(!enabled)
        }
        .opacity(enabled ? 1 : 0.55)
    }

    private var canApplyBrandMarkToQueue: Bool {
        session.brandMarkIsActive && queueApplyTargetCount > 0
    }

    private var queueApplyTargetCount: Int {
        session.products.filter { !$0.isCompositeBundle }.count
    }

    private var queueApplyHelpText: String {
        if session.products.isEmpty {
            return "Add photos to the queue first."
        }
        if !session.brandMarkEnabled {
            return "Enable Brand Kit and configure text and/or logo, then apply to existing queue photos."
        }
        if !session.brandMarkIsActive {
            return "Turn on Show text (with a name) and/or Show logo before applying to the queue."
        }
        return "Updates \(queueApplyTargetCount) queue photo\(queueApplyTargetCount == 1 ? "" : "s") with the current Brand Kit. Does not change photos that use Hide Brand Kit."
    }

    private var fontSizeMenuItems: [DSDropdownActionItem] {
        var items = BrandMarkFontSizePreset.options.map { pt in
            DSDropdownActionItem.action(
                "\(pt)",
                "\(pt) pt",
                isSelected: session.brandMarkFontSizePx == pt
            )
        }
        items.append(.divider("font-size-custom-divider"))
        let customSelected = !BrandMarkFontSizePreset.isPreset(session.brandMarkFontSizePx)
        items.append(.action(
            "custom",
            customSelected ? "Custom (\(session.brandMarkFontSizePx) pt)…" : "Custom…",
            isSelected: customSelected
        ))
        return items
    }

    private var fontControlsRow: some View {
        let textEnabled = session.brandMarkEnabled && session.brandMarkShowText
        return HStack(spacing: 8) {
            DSDropdownActionMenu(
                label: {
                    brandMarkFontTabLabel(title: "Size", value: "\(session.brandMarkFontSizePx) pt")
                },
                items: fontSizeMenuItems,
                isEnabled: textEnabled
            ) { item in
                if item.id == "custom" {
                    customFontSizeText = "\(session.brandMarkFontSizePx)"
                    showCustomFontSizeAlert = true
                } else if let px = Int(item.id) {
                    InteractionHaptics.selection()
                    session.brandMarkFontSizePx = px
                }
            }

            DSDropdownActionMenu(
                label: {
                    brandMarkFontTabLabel(title: "Style", value: session.brandMarkFontStyle.title)
                },
                items: BrandMarkFontStyle.allCases.map { style in
                    .action(style.rawValue, style.title, isSelected: session.brandMarkFontStyle == style)
                },
                isEnabled: textEnabled
            ) { item in
                if let style = BrandMarkFontStyle(rawValue: item.id) {
                    InteractionHaptics.selection()
                    session.brandMarkFontStyle = style
                    schedulePreviewRefresh()
                }
            }

            Button {
                guard textEnabled else { return }
                InteractionHaptics.selection()
                showFontPicker = true
            } label: {
                brandMarkFontTabLabel(
                    title: "Font",
                    value: session.brandMarkConfiguration.fontDisplayName,
                    chevron: "textformat"
                )
            }
            .buttonStyle(.plainPressable)
            .disabled(!textEnabled)
        }
    }

    private func commitCustomFontSize() {
        let cleaned = customFontSizeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(cleaned) else { return }
        InteractionHaptics.selection()
        session.brandMarkFontSizePx = BrandMarkFontSizePreset.clamped(value)
    }

    private func commitImageNameCustomFontSize() {
        let cleaned = imageNameCustomFontSizeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(cleaned) else { return }
        InteractionHaptics.selection()
        session.imageNameStampFontSizePx = BrandMarkFontSizePreset.clamped(value)
    }

    private var imageNameFontSizeMenuItems: [DSDropdownActionItem] {
        var items = BrandMarkFontSizePreset.options.map { pt in
            DSDropdownActionItem.action(
                "\(pt)",
                "\(pt) pt",
                isSelected: session.imageNameStampFontSizePx == pt
            )
        }
        items.append(.divider("image-name-font-size-custom-divider"))
        let customSelected = !BrandMarkFontSizePreset.isPreset(session.imageNameStampFontSizePx)
        items.append(.action(
            "custom",
            customSelected ? "Custom (\(session.imageNameStampFontSizePx) pt)…" : "Custom…",
            isSelected: customSelected
        ))
        return items
    }

    private var imageNameFontControlsRow: some View {
        HStack(spacing: 8) {
            DSDropdownActionMenu(
                label: {
                    brandMarkFontTabLabel(title: "Size", value: "\(session.imageNameStampFontSizePx) pt")
                },
                items: imageNameFontSizeMenuItems,
                isEnabled: true
            ) { item in
                if item.id == "custom" {
                    imageNameCustomFontSizeText = "\(session.imageNameStampFontSizePx)"
                    showImageNameCustomFontSizeAlert = true
                } else if let pt = Int(item.id) {
                    InteractionHaptics.selection()
                    session.imageNameStampFontSizePx = pt
                }
            }

            DSDropdownActionMenu(
                label: {
                    brandMarkFontTabLabel(title: "Style", value: session.imageNameStampFontStyle.title)
                },
                items: BrandMarkFontStyle.allCases.map { style in
                    .action(style.rawValue, style.title, isSelected: session.imageNameStampFontStyle == style)
                },
                isEnabled: true
            ) { item in
                if let style = BrandMarkFontStyle(rawValue: item.id) {
                    InteractionHaptics.selection()
                    session.imageNameStampFontStyle = style
                    schedulePreviewRefresh()
                }
            }

            Button {
                InteractionHaptics.selection()
                showImageNameFontPicker = true
            } label: {
                brandMarkFontTabLabel(
                    title: "Font",
                    value: session.brandMarkConfiguration.imageName.fontDisplayName,
                    chevron: "textformat"
                )
            }
            .buttonStyle(.plainPressable)
        }
    }

    private var imageNameColorPresetsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Color presets")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.ColorToken.label)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BrandMarkColorPreset.all) { preset in
                        let selected = session.brandMarkConfiguration.imageName.matchedColorPreset?.id == preset.id
                        Button {
                            InteractionHaptics.selection()
                            session.applyImageNameColorPreset(preset)
                        } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color(hex: preset.plateColorHex))
                                        .frame(width: 44, height: 32)
                                    Text("Aa")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(Color(hex: preset.fontColorHex))
                                }
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(
                                            selected ? DS.ColorToken.accent : DS.ColorToken.separator,
                                            lineWidth: selected ? 2 : 1
                                        )
                                )
                                Text(preset.name)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(selected ? DS.ColorToken.accent : DS.ColorToken.secondaryLabel)
                                    .lineLimit(1)
                            }
                            .frame(width: 58)
                        }
                        .buttonStyle(.plainPressable)
                    }
                }
            }
        }
    }

    private var previewImageNameLabel: String {
        if let product = session.products.first(where: { !$0.isCompositeBundle }) {
            return FileNameRules.baseName(for: product, namingMode: session.imageNamingMode)
        }
        return "Image-Name"
    }

    private func brandMarkFontTabLabel(title: String, value: String, chevron: String = "chevron.up.chevron.down") -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DS.ColorToken.secondaryLabel)
                .lineLimit(1)
            HStack(spacing: 4) {
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.ColorToken.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
                Image(systemName: chevron)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DS.ColorToken.secondaryLabel)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.ColorToken.backgroundTertiary, in: RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                .stroke(DS.ColorToken.separator, lineWidth: 1)
        )
    }

    private var colorPresetsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Color presets")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.ColorToken.label)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BrandMarkColorPreset.all) { preset in
                        let selected = session.brandMarkConfiguration.matchedColorPreset?.id == preset.id
                        Button {
                            InteractionHaptics.selection()
                            session.applyBrandMarkColorPreset(preset)
                        } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color(hex: preset.plateColorHex))
                                        .frame(width: 44, height: 32)
                                    Text("Aa")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(Color(hex: preset.fontColorHex))
                                }
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(
                                            selected ? DS.ColorToken.accent : DS.ColorToken.separator,
                                            lineWidth: selected ? 2 : 1
                                        )
                                )
                                Text(preset.name)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(selected ? DS.ColorToken.accent : DS.ColorToken.secondaryLabel)
                                    .lineLimit(1)
                            }
                            .frame(width: 58)
                        }
                        .buttonStyle(.plainPressable)
                        .accessibilityLabel("\(preset.name) color preset")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
        }
    }

    private func colorPickerRow(title: String, hex: Binding<String>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.ColorToken.label)
            Spacer()
            ColorPicker(
                "",
                selection: Binding(
                    get: { Color(uiColor: UIColor(hexString: hex.wrappedValue) ?? .white) },
                    set: { hex.wrappedValue = UIColor($0).hexString }
                ),
                supportsOpacity: false
            )
            .labelsHidden()
        }
    }

    private func opacitySliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        enabled: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.ColorToken.label)
                Spacer()
                Text("\(Int(value.wrappedValue * 100))%")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.ColorToken.secondaryLabel)
                    .frame(minWidth: 36, alignment: .trailing)
            }
            Slider(value: value, in: range, step: 0.01)
                .tint(DS.ColorToken.accent)
                .disabled(!enabled)
        }
        .opacity(enabled ? 1 : 0.55)
    }

    private func positionGrid(
        selected: BrandMarkPosition,
        blocked: BrandMarkPosition?,
        enabled: Bool,
        onSelect: @escaping (BrandMarkPosition) -> Void
    ) -> some View {
        VStack(spacing: 8) {
            ForEach(Array(BrandMarkPosition.gridRows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(row) { position in
                        let isSelected = selected == position
                        let isBlocked = BrandMarkPositionConflict.isBlocked(position, by: blocked)
                        Button {
                            guard !isBlocked else { return }
                            InteractionHaptics.selection()
                            onSelect(position)
                        } label: {
                            Text(isBlocked ? "—" : position.gridLetter)
                                .font(.system(size: 13, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .foregroundStyle(
                                    isBlocked
                                        ? DS.ColorToken.tertiaryLabel
                                        : (isSelected ? Color.white : DS.ColorToken.label)
                                )
                                .background(
                                    isBlocked
                                        ? DS.ColorToken.backgroundTertiary.opacity(0.55)
                                        : (isSelected ? DS.ColorToken.accent : DS.ColorToken.backgroundTertiary),
                                    in: RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                                        .stroke(DS.ColorToken.separator, lineWidth: isSelected || isBlocked ? 0 : 1)
                                )
                        }
                        .buttonStyle(.plainPressable)
                        .disabled(!enabled || isBlocked)
                        .accessibilityLabel(
                            isBlocked
                                ? "\(position.title), used by the other stamp"
                                : position.title
                        )
                    }
                }
            }
        }
    }

    private var liveCanvasPreview: some View {
        DSSectionCard(title: "Live canvas", icon: "eye") {
            Group {
                if let previewImage {
                    Image(uiImage: previewImage)
                        .resizable()
                        .aspectRatio(previewImage.size.width / max(previewImage.size.height, 1), contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                                .stroke(DS.ColorToken.separator, lineWidth: 1)
                        )
                        .id(session.brandMarkSettingsRevision)
                        .accessibilityLabel("Brand Kit live preview")
                } else {
                    RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                        .fill(DS.ColorToken.backgroundTertiary)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                        .overlay(ProgressView().controlSize(.small))
                }
            }
            DSHelperText(
                session.products.first != nil
                    ? "Same stamp as queue photos (scaled to match canvas). Adjust text, logo, and position below."
                    : "Sample canvas until you add a photo to the queue."
            )
        }
    }

    /// Rebuild mark-free base from the original capture so Live Canvas never double-stamps.
    private func scheduleMarkFreeBaseRefresh() {
        markFreeBaseTask?.cancel()
        previewTask?.cancel()
        guard let product = session.products.first(where: { !$0.isCompositeBundle }) else {
            markFreePreviewBase = nil
            markFreeBaseProductID = nil
            markFreeBaseUnavailable = false
            schedulePreviewRefresh()
            return
        }
        let productID = product.id
        if markFreeBaseProductID == productID, markFreePreviewBase != nil {
            schedulePreviewRefresh()
            return
        }
        markFreePreviewBase = nil
        markFreeBaseProductID = productID
        markFreeBaseUnavailable = false
        previewImage = nil

        let removeBG = product.backgroundRemoved || session.autoBackgroundRemoval
        let canvasW = product.canvasWidth
        let canvasH = product.canvasHeight
        let fill = product.fillRatio
        let polish = product.polishEnabled
        let mode = product.enhancementMode
        let strength = product.studioAIStrength
        let bg = product.backgroundColor
        let bg2 = product.secondaryBackgroundColor
        let style = product.backgroundStyle
        let hexes = product.gradientColorHexes
        let fillSpec = product.resolvedBackgroundFillSpec
        let filter = product.photoFilter
        let filterIntensity = product.photoFilterIntensity
        let autoEnhance = product.adjustAutoEnhance
        let rotation = product.rotationDegrees
        let flipH = product.flipHorizontal
        let flipV = product.flipVertical
        let smartColor = session.smartColorAccuracyEnabled

        markFreeBaseTask = Task(priority: .userInitiated) {
            // Never fall back to the stamped queue image — that causes double-stamp ghosting.
            guard let original = await QueueImageResolver.uncompressedOriginal(
                for: product,
                fallbackToProcessed: false
            ) else {
                await MainActor.run {
                    markFreePreviewBase = nil
                    markFreeBaseProductID = nil
                    markFreeBaseUnavailable = true
                    schedulePreviewRefresh()
                }
                return
            }
            guard !Task.isCancelled else { return }
            let base = await Task.detached(priority: .userInitiated) {
                let capped = ImageProcessor.downsampleIfNeededForImportPipeline(
                    original,
                    maxLongEdgePixels: 960
                )
                return ImageProcessor.processForExport(
                    capped,
                    removeBackground: removeBG,
                    canvasWidth: canvasW,
                    canvasHeight: canvasH,
                    rotationDegrees: rotation,
                    fillRatio: fill,
                    polishEnabled: polish,
                    enhancementMode: mode,
                    studioAIStrength: strength,
                    backgroundColor: bg,
                    secondaryBackgroundColor: bg2,
                    backgroundStyle: style,
                    gradientColorHexes: hexes,
                    backgroundFillSpec: fillSpec,
                    smartColorAccuracy: smartColor,
                    smartUpscale: false,
                    flipHorizontal: flipH,
                    flipVertical: flipV,
                    photoFilter: filter,
                    photoFilterIntensity: filterIntensity,
                    adjustAutoEnhance: autoEnhance,
                    applyBrandMark: false
                ).image
            }.value
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard markFreeBaseProductID == productID else { return }
                markFreePreviewBase = base
                schedulePreviewRefresh()
            }
        }
    }

    private func schedulePreviewRefresh() {
        previewTask?.cancel()
        let config = session.brandMarkConfiguration
        let markFreeBase = markFreePreviewBase
        let imageNameLabel = previewImageNameLabel
        let hasQueuePhoto = session.products.contains(where: { !$0.isCompositeBundle })
        // Wait for mark-free base so we never stamp on an already-stamped queue image.
        if hasQueuePhoto, markFreeBase == nil, !markFreeBaseUnavailable { return }
        previewTask = Task(priority: .userInitiated) {
            try? await Task.sleep(nanoseconds: 70_000_000)
            guard !Task.isCancelled else { return }
            let image = await Task.detached(priority: .userInitiated) {
                BrandMarkRenderer.previewImage(
                    configuration: config,
                    sampleProduct: markFreeBase,
                    imageNameText: imageNameLabel
                )
            }.value
            guard !Task.isCancelled else { return }
            await MainActor.run { previewImage = image }
        }
    }

    private func importLogoFromPhotos(_ item: PhotosPickerItem) async {
        logoError = nil
        defer { selectedPhotoItems = [] }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = ImageImportDecoder.uiImage(from: data) ?? UIImage(data: data) else {
            await MainActor.run { logoError = "Could not load that photo." }
            return
        }
        await MainActor.run {
            if session.importBrandMarkLogo(image) {
                logoError = nil
            } else {
                logoError = "Could not save the logo."
            }
            schedulePreviewRefresh()
        }
    }

    private func importLogoFromFiles(_ result: Result<[URL], Error>) {
        logoError = nil
        switch result {
        case .failure:
            logoError = "Could not open the selected file."
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                logoError = "Could not access the selected file."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let data = try? Data(contentsOf: url),
                  let image = ImageImportDecoder.uiImage(from: data) ?? UIImage(data: data) else {
                logoError = "The file is not a supported image."
                return
            }
            if session.importBrandMarkLogo(image) {
                logoError = nil
            } else {
                logoError = "Could not save the logo."
            }
            schedulePreviewRefresh()
        }
    }
}

/// Same system font picker Markup uses for “Choose Font”.
private struct BrandMarkSystemFontPicker: UIViewControllerRepresentable {
    @Binding var postScriptName: String?
    var onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(postScriptName: $postScriptName, onDismiss: onDismiss)
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let picker = UIFontPickerViewController()
        picker.delegate = context.coordinator
        let nav = UINavigationController(rootViewController: picker)
        picker.navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "System",
            style: .plain,
            target: context.coordinator,
            action: #selector(Coordinator.useSystemFont)
        )
        picker.navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: context.coordinator,
            action: #selector(Coordinator.cancel)
        )
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    final class Coordinator: NSObject, UIFontPickerViewControllerDelegate {
        var postScriptName: Binding<String?>
        var onDismiss: () -> Void

        init(postScriptName: Binding<String?>, onDismiss: @escaping () -> Void) {
            self.postScriptName = postScriptName
            self.onDismiss = onDismiss
        }

        func fontPickerViewControllerDidPickFont(_ viewController: UIFontPickerViewController) {
            if let desc = viewController.selectedFontDescriptor {
                let font = UIFont(descriptor: desc, size: 17)
                postScriptName.wrappedValue = font.fontDescriptor.postscriptName
            }
            onDismiss()
        }

        func fontPickerViewControllerDidCancel(_ viewController: UIFontPickerViewController) {
            onDismiss()
        }

        @objc func cancel() {
            onDismiss()
        }

        @objc func useSystemFont() {
            postScriptName.wrappedValue = nil
            onDismiss()
        }
    }
}
