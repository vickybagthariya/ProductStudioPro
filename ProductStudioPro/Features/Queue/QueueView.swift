import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers

struct QueueView: View {
    @EnvironmentObject private var session: CaptureSessionStore
    @EnvironmentObject private var loadingState: LoadingStateManager
    @State private var sharePayload: SharePayload?
    @State private var previewIndex: Int?
    @State private var replacingProduct: CapturedProduct?
    @State private var showReplaceCamera = false
    @State private var showClearConfirm = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showFileImporter = false
    @State private var showSyncLookSheet = false
    @State private var syncLookSource: CapturedProduct?
    @State private var renamingProduct: CapturedProduct?
    @State private var renameText = ""
    @State private var isSelectionMode = false
    @State private var selectedProductIDs: Set<UUID> = []
    @State private var showBulkDeleteConfirm = false
    @State private var showBulkResetConfirm = false
    @State private var searchText = ""
    @State private var isSearchPresented = false
    @FocusState private var isSearchFieldFocused: Bool
    @State private var queueFilter: QueueDashboardFilter = .all
    @State private var sortOption: QueueSortOption = .newestFirst
    @State private var groupByUPC = false
    /// When non-nil, full-width export sheet offers format choices for these products.
    @State private var shareDialogProducts: [CapturedProduct]?
    @State private var pendingCSVFormatAsk: ShareCSVFormatAsk?
    @State private var postShareRemovalCandidates: [UUID] = []
    @State private var showPostShareRemoveConfirm = false
    @State private var showGroupedCoverEditor = false
    @State private var showGroupedCoverNamePrompt = false
    @State private var groupedCoverNameText = ""
    @State private var groupedCoverEditingProductID: UUID?
    @State private var groupedCoverExistingLayout: CompositeBundleLayout?
    @State private var groupedCoverNamePromptError = false
    @State private var showSessionManager = false
    @State private var showAddToFolderSheet = false
    @State private var folderMoveToast: String?

    var body: some View {
        queueNavigationStack
            .onDisappear {
                session.cancelActiveBulkWork()
            }
    }

    private var queueNavigationStack: some View {
        queueMainColumn
        .navigationBarHidden(true)
        .onChange(of: selectedPhotoItems) { _, newItems in importSelectedPhotos(newItems) }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            importFiles(result)
        }
        .alert("Edit image name", isPresented: Binding(
            get: { renamingProduct != nil },
            set: { if !$0 { renamingProduct = nil } }
        )) {
            TextField("Image name", text: $renameText)
            Button("Cancel", role: .cancel) { renamingProduct = nil }
            Button("Save") {
                if let product = renamingProduct { session.renameProduct(product, to: renameText) }
                renamingProduct = nil
            }
        } message: {
            Text("This updates the exported .jpg filename. You can change it even after UPC scan or import.")
        }
        .alert("Clear queue?", isPresented: $showClearConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear Queue", role: .destructive) { session.clearQueue() }
        } message: { Text("This removes all queued products from this session.") }
        .alert("Delete selected images?", isPresented: $showBulkDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                session.removeProducts(ids: selectedProductIDs)
                selectedProductIDs.removeAll()
                isSelectionMode = false
            }
        } message: { Text("This removes the selected images from the queue only.") }
        .alert("Reset selected images?", isPresented: $showBulkResetConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reset") {
                previewIndex = nil
                session.resetProductsToOriginal(ids: selectedProductIDs)
            }
        } message: {
            Text("Reprocesses each selected image from its original photo using your current session settings. Filters, rotation, and markup edits are cleared.")
        }
        .sheet(isPresented: $showSyncLookSheet) {
            if let source = syncLookSource {
                SyncLookSheet(
                    source: source,
                    targetIDs: selectedProductIDs,
                    onSync: {
                        session.matchLook(from: source, to: selectedProductIDs)
                    }
                )
                .environmentObject(session)
            }
        }
        .sheet(item: $sharePayload, onDismiss: clearExportUIState) { payload in
            ActivityView(activityItems: payload.items) { _, completed, _, _ in
                Task { @MainActor in
                    sharePayload = nil
                    clearExportUIState()
                    if completed, !payload.productIDsForRemovalPrompt.isEmpty {
                        postShareRemovalCandidates = payload.productIDsForRemovalPrompt
                        showPostShareRemoveConfirm = true
                    }
                }
            }
        }
        .alert("Remove shared images from the queue?", isPresented: $showPostShareRemoveConfirm) {
            Button("Keep in queue", role: .cancel) { postShareRemovalCandidates = [] }
            Button("Remove from queue", role: .destructive) {
                let ids = Set(postShareRemovalCandidates)
                session.removeProducts(ids: ids)
                selectedProductIDs.subtract(ids)
                postShareRemovalCandidates = []
            }
        } message: {
            Text("You finished sharing \(postShareRemovalCandidates.count) item(s). Remove them from Product Studio Pro’s queue? This does not delete files you saved elsewhere.")
        }
        .sheet(isPresented: Binding(
            get: { previewIndex != nil },
            set: { if !$0 { previewIndex = nil } }
        )) {
            ImagePreviewPagerView(initialIndex: previewIndex ?? 0)
                .environment(\.loadingState, loadingState)
        }
        .fullScreenCover(isPresented: $showReplaceCamera) {
            CameraCaptureView(
                settings: session.preferredCameraSettings,
                onSettingsCaptured: { settings in
                    session.rememberCameraPreferences(from: settings)
                },
                onCapture: { image in
                    if let product = replacingProduct { session.replaceImage(for: product, with: image) }
                    replacingProduct = nil
                    showReplaceCamera = false
                },
                onCancel: {
                    replacingProduct = nil
                    showReplaceCamera = false
                }
            )
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showGroupedCoverEditor) {
            GroupedCoverEditorSheet(
                sourceProducts: groupedCoverSourceProducts,
                canvasWidth: GroupedCoverDefaults.canvasWidth,
                canvasHeight: GroupedCoverDefaults.canvasHeight,
                fillRatio: session.outputFillRatio,
                backgroundFillSpec: BackgroundFillSpec.fromLegacy(
                    style: session.backgroundCanvasStyle,
                    hexes: session.gradientColorHexes
                ),
                primaryColor: session.backgroundColor,
                secondaryColor: session.secondaryBackgroundColor,
                coverName: groupedCoverNameText,
                existingLayout: groupedCoverExistingLayout,
                editingProductID: groupedCoverEditingProductID,
                onSave: { image, layout in
                    let sources = groupedCoverSourceProducts
                    if let editingID = groupedCoverEditingProductID {
                        session.updateGroupedCover(
                            productID: editingID,
                            compositeImage: image,
                            layout: layout,
                            name: groupedCoverNameText
                        )
                    } else {
                        let item = session.insertGroupedCover(
                            compositeImage: image,
                            layout: layout,
                            sourceProducts: sources,
                            name: groupedCoverNameText
                        )
                        isSelectionMode = false
                        selectedProductIDs.removeAll()
                        if let idx = session.products.firstIndex(where: { $0.id == item.id }) {
                            previewIndex = idx
                        }
                    }
                    groupedCoverEditingProductID = nil
                    groupedCoverExistingLayout = nil
                },
                onCancel: {
                    groupedCoverEditingProductID = nil
                    groupedCoverExistingLayout = nil
                }
            )
        }
        .sheet(isPresented: $showGroupedCoverNamePrompt) {
            groupedCoverNameEntrySheet
        }
        .sheet(isPresented: shareDialogPresented) {
            ExportShareOptionsSheet(
                title: shareDialogTitle,
                message: shareDialogMessage,
                isSingleImage: (shareDialogProducts?.count ?? 0) <= 1,
                onZip: {
                    if let p = shareDialogProducts { shareZip(products: p, includeCSV: true) }
                    shareDialogProducts = nil
                },
                onJPG: {
                    if let p = shareDialogProducts { pendingCSVFormatAsk = .jpg(p) }
                    shareDialogProducts = nil
                },
                onPNG: {
                    if let p = shareDialogProducts { pendingCSVFormatAsk = .png(p) }
                    shareDialogProducts = nil
                },
                onCSV: {
                    if let p = shareDialogProducts { shareCSVOnly(products: p) }
                    shareDialogProducts = nil
                },
                onCancel: { shareDialogProducts = nil }
            )
        }
        .alert("Include CSV manifest?", isPresented: pendingCSVAskPresented) {
            Button("Images + CSV") {
                guard let ask = pendingCSVFormatAsk else { return }
                share(products: ask.products, includeCSV: true, format: ask.format)
                pendingCSVFormatAsk = nil
            }
            Button("Images only") {
                guard let ask = pendingCSVFormatAsk else { return }
                share(products: ask.products, includeCSV: false, format: ask.format)
                pendingCSVFormatAsk = nil
            }
            Button("Cancel", role: .cancel) { pendingCSVFormatAsk = nil }
        } message: {
            Text(pendingCSVFormatAsk?.format == .png
                 ? "PNG exports keep transparency when backgrounds were removed. Add a CSV inventory list?"
                 : "Add a CSV inventory list alongside the JPG files?")
        }
        .sheet(isPresented: $showSessionManager) {
            CatalogSessionManagerSheet()
                .environmentObject(session)
        }
        .sheet(isPresented: $showAddToFolderSheet) {
            AddToSessionFolderSheet(productIDs: selectedProductIDs) { message in
                selectedProductIDs.removeAll()
                isSelectionMode = false
                folderMoveToast = message
                Task {
                    try? await Task.sleep(nanoseconds: 2_400_000_000)
                    await MainActor.run {
                        if folderMoveToast == message { folderMoveToast = nil }
                    }
                }
            }
            .environmentObject(session)
        }
    }

    private var queueMainColumn: some View {
        AppScreenScaffold(
            title: queueHeaderTitle,
            subtitle: queueHeaderSubtitle,
            showsHome: false,
            onBack: { session.popNavigation() },
            onHome: { session.goHome() },
            layout: .listBody,
            headerAccessory: { queueHeaderAccessory }
        ) {
            QueueCollapsibleSearchBar(
                text: $searchText,
                isPresented: $isSearchPresented,
                focusBinding: $isSearchFieldFocused
            )
            .animation(PSDesignMotion.springSoft, value: isSearchPresented)

            compactActionButtons

            QueueDashboardFilterRow(selectedFilter: $queueFilter)
                .padding(.bottom, PSDesignSpacing.xs)

            if filteredProducts.isEmpty {
                emptyState
            } else if groupByUPC {
                List {
                    ForEach(upcGroupedSections, id: \.upc) { section in
                        Section {
                            ForEach(section.products) { product in
                                queueRowWithActions(product)
                            }
                        } header: {
                            HStack {
                                Text(section.upc)
                                    .font(DS.TypeScale.caption.weight(.semibold))
                                    .foregroundStyle(DS.ColorToken.label)
                                Spacer()
                                Text("\(section.products.count) angle\(section.products.count == 1 ? "" : "s")")
                                    .font(DS.TypeScale.micro)
                                    .foregroundStyle(DS.ColorToken.secondaryLabel)
                            }
                            .textCase(nil)
                        }
                    }
                }
                .listRowSpacing(4)
                .scrollContentBackground(.hidden)
                .listStyle(.plain)
            } else {
                List {
                    ForEach(filteredProducts) { product in
                        queueRowWithActions(product)
                    }
                }
                .listRowSpacing(4)
                .scrollContentBackground(.hidden)
                .listStyle(.plain)
            }

            bulkActionBar
                .opacity(isSelectionMode ? 1 : 0)
                .frame(minHeight: 44)
                .allowsHitTesting(isSelectionMode)
                .accessibilityHidden(!isSelectionMode)

            exportButtons
        } footer: {
            EmptyView()
        }
        .overlay(alignment: .top) {
            if let folderMoveToast {
                Text(folderMoveToast)
                    .font(DS.TypeScale.caption.weight(.semibold))
                    .foregroundStyle(DS.ColorToken.onAccent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(DS.ColorToken.primaryButtonFill, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: folderMoveToast)
        .allowsHitTesting(session.activeImport == nil)
    }

    private var shareDialogPresented: Binding<Bool> {
        Binding(
            get: { shareDialogProducts != nil },
            set: { if !$0 { shareDialogProducts = nil } }
        )
    }

    private var pendingCSVAskPresented: Binding<Bool> {
        Binding(
            get: { pendingCSVFormatAsk != nil },
            set: { if !$0 { pendingCSVFormatAsk = nil } }
        )
    }

    private var shareDialogTitle: String {
        let n = shareDialogProducts?.count ?? 0
        return n == 1 ? "Export 1 image" : "Export \(n) images"
    }

    private var shareDialogMessage: String {
        let n = shareDialogProducts?.count ?? 0
        if n <= 1 {
            return "Recommended for one photo: JPG (or PNG cutout). ZIP packs JPG + CSV for handoff."
        }
        return "Recommended for \(n) photos: ZIP (JPG + CSV). JPG/PNG also work for bulk export."
    }

    /// When the user is in Select mode with at least one row checked, bulk actions use that subset only.
    private var bulkShareTargets: [CapturedProduct] {
        if isSelectionMode, !selectedProductIDs.isEmpty {
            return session.products.filter { selectedProductIDs.contains($0.id) }
        }
        return session.products
    }

    private func openShareDialog(for products: [CapturedProduct]) {
        guard !products.isEmpty else { return }
        InteractionHaptics.tap(vibrate: session.vibrateEnabled)
        shareDialogProducts = products
    }

    private var queueHeaderTitle: String {
        "\(session.activeCatalogSessionName) Queue"
    }

    private var queueHeaderSubtitle: String {
        let total = session.products.count
        let visible = filteredProducts.count
        let imageLabel = visible == 1 ? "image" : "images"
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || queueFilter != .all {
            return "\(visible) of \(total) \(imageLabel). Long-press to multi-select."
        }
        return "\(total) \(imageLabel). Long-press to multi-select."
    }

    private var queueHeaderAccessory: some View {
        HStack(spacing: DS.Space.tight) {
            Button {
                InteractionHaptics.tap(vibrate: session.vibrateEnabled)
                withAnimation(PSDesignMotion.springSoft) {
                    isSearchPresented.toggle()
                    if isSearchPresented {
                        Task { @MainActor in
                            await Task.yield()
                            isSearchFieldFocused = true
                        }
                    } else {
                        searchText = ""
                        isSearchFieldFocused = false
                    }
                }
            } label: {
                Image(systemName: isSearchPresented ? "xmark" : "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSearchPresented ? PSDesignColors.textPrimary : DS.ColorToken.accent)
                    .frame(width: 34, height: 34)
                    .background(DS.ColorToken.backgroundTertiary, in: Circle())
                    .overlay(Circle().stroke(DS.ColorToken.separator, lineWidth: 1))
            }
            .buttonStyle(.plainPressable)
            .accessibilityLabel(isSearchPresented ? "Close search" : "Search queue")

            Button {
                showSessionManager = true
            } label: {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.ColorToken.accent)
                    .frame(width: 34, height: 34)
                    .background(DS.ColorToken.backgroundTertiary, in: Circle())
                    .overlay(Circle().stroke(DS.ColorToken.separator, lineWidth: 1))
            }
            .buttonStyle(.plainPressable)
            .accessibilityLabel("Switch or manage sessions")
            .accessibilityHint("Create, switch, rename, or delete queue sessions")

            DSDropdownActionMenu(
                label: {
                    Image(systemName: "arrow.up.arrow.down.circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(session.products.isEmpty ? DS.ColorToken.tertiaryLabel : DS.ColorToken.accent)
                        .frame(width: 34, height: 34)
                        .background(DS.ColorToken.backgroundTertiary, in: Circle())
                        .overlay(Circle().stroke(DS.ColorToken.separator, lineWidth: 1))
                },
                items: QueueSortOption.allCases.map { option in
                    .action(option.rawValue, option.rawValue, isSelected: sortOption == option)
                },
                isEnabled: !session.products.isEmpty
            ) { item in
                if let option = QueueSortOption.allCases.first(where: { $0.rawValue == item.id }) {
                    sortOption = option
                }
            }
            .accessibilityLabel("Sort queue")

            Button {
                groupByUPC.toggle()
            } label: {
                Image(systemName: groupByUPC ? "square.grid.3x1.folder.fill.badge.plus" : "square.grid.3x1.folder.badge.plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(session.products.isEmpty ? DS.ColorToken.tertiaryLabel : (groupByUPC ? DS.ColorToken.accent : DS.ColorToken.secondaryLabel))
                    .frame(width: 34, height: 34)
                    .background(DS.ColorToken.backgroundTertiary, in: Circle())
                    .overlay(Circle().stroke(DS.ColorToken.separator, lineWidth: 1))
            }
            .buttonStyle(.plainPressable)
            .disabled(session.products.isEmpty)
            .accessibilityLabel(groupByUPC ? "Ungroup queue" : "Group by UPC")
            .accessibilityHint("Groups multi-angle photos that share the same UPC")

            Button {
                if isSelectionMode {
                    isSelectionMode = false
                    selectedProductIDs.removeAll()
                } else {
                    isSelectionMode = true
                }
            } label: {
                Text(isSelectionMode ? "Done" : "Select")
                    .font(DS.TypeScale.caption.weight(.semibold))
                    .foregroundStyle(session.products.isEmpty ? DS.ColorToken.tertiaryLabel : DS.ColorToken.accent)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .background(DS.ColorToken.backgroundTertiary, in: Capsule())
                    .overlay(Capsule().stroke(DS.ColorToken.separator, lineWidth: 1))
            }
            .buttonStyle(.plainPressable)
            .disabled(session.products.isEmpty)
            .accessibilityLabel(isSelectionMode ? "Done selecting" : "Select photos")
            .accessibilityHint(isSelectionMode ? "Exits bulk select mode" : "Turns on bulk select mode for the queue")
        }
    }

    private var compactActionButtons: some View {
        let isImportingPhotos = session.activeImport != nil
        return HStack(spacing: PSDesignSpacing.sm) {
            PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 100, matching: .images) {
                Label(isImportingPhotos ? "Importing" : "Upload", systemImage: "photo.on.rectangle")
                    .labelStyle(.titleAndIcon)
                    .font(PSDesignTypography.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, PSDesignSpacing.sm)
            }
            .buttonStyle(CompactSecondaryButtonStyle())
            .disabled(isImportingPhotos)

            Button { showFileImporter = true } label: {
                Label("Apps", systemImage: "folder")
                    .labelStyle(.titleAndIcon)
                    .font(PSDesignTypography.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, PSDesignSpacing.sm)
            }
            .buttonStyle(CompactSecondaryButtonStyle())
            .disabled(isImportingPhotos)

            Button {
                session.navigationPath.append(AppRoute.singleCapture)
            } label: {
                Label("Single", systemImage: "camera")
                    .labelStyle(.titleAndIcon)
                    .font(PSDesignTypography.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, PSDesignSpacing.sm)
            }
            .buttonStyle(CompactSecondaryButtonStyle())

            Button {
                session.navigationPath.append(AppRoute.batchCapture)
            } label: {
                Label("Batch", systemImage: "square.stack")
                    .labelStyle(.titleAndIcon)
                    .font(PSDesignTypography.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, PSDesignSpacing.sm)
            }
            .buttonStyle(CompactSecondaryButtonStyle())
        }
    }

    private var bulkActionBar: some View {
        let allFilteredSelected = selectedProductIDs.count == filteredProducts.count && !filteredProducts.isEmpty
        return QueueBulkSelectionBar(
            selectedCount: selectedProductIDs.count,
            showGroupedCover: groupedCoverSelectionEnabled,
            selectAllTitle: allFilteredSelected ? "Clear" : "All",
            folderEnabled: !selectedProductIDs.isEmpty,
            bulkMenuItems: bulkSelectionActionItems,
            bulkMenuEnabled: !selectedProductIDs.isEmpty,
            onGroupedCover: {
                groupedCoverNameText = ""
                groupedCoverNamePromptError = false
                showGroupedCoverNamePrompt = true
            },
            onFolder: {
                guard !selectedProductIDs.isEmpty else { return }
                InteractionHaptics.tap(vibrate: session.vibrateEnabled)
                showAddToFolderSheet = true
            },
            onSelectAllToggle: {
                if allFilteredSelected {
                    selectedProductIDs.removeAll()
                } else {
                    selectedProductIDs = Set(filteredProducts.map(\.id))
                }
            },
            onBulkMenuAction: handleBulkSelectionAction
        )
    }

    private var groupedCoverSelectionEnabled: Bool {
        (2...20).contains(selectedProductIDs.count)
    }

    private var groupedCoverSourceProducts: [CapturedProduct] {
        session.products.filter { selectedProductIDs.contains($0.id) }
    }

    private var bulkSelectionActionItems: [DSDropdownActionItem] {
        var items: [DSDropdownActionItem] = [
            .header("PRODUCTIVITY"),
            .action("enhance", "Enhance", systemImage: "sparkles", isDisabled: selectedProductIDs.isEmpty),
            .action("match-look", "Apply Look…", systemImage: "paintbrush.pointed", isDisabled: selectedProductIDs.count < 2),
            .action("add-folder", "Add to folder…", systemImage: "folder.badge.plus", isDisabled: selectedProductIDs.isEmpty),
            .header("OUTPUT"),
            .action("share", "Export…", systemImage: "square.and.arrow.up", isDisabled: selectedProductIDs.isEmpty),
        ]
        if session.brandMarkEnabled {
            items.append(.header("BRAND KIT"))
            items.append(.action(
                "show-brand-mark",
                "Show Brand Mark",
                systemImage: "seal",
                isDisabled: selectedProductIDs.isEmpty
            ))
            items.append(.action(
                "hide-brand-mark",
                "Hide Brand Mark",
                systemImage: "seal.slash",
                isDisabled: selectedProductIDs.isEmpty
            ))
        }
        items.append(.header("RESET / DESTRUCTIVE"))
        items.append(.action("reset", "Reset", systemImage: "arrow.counterclockwise", isDisabled: selectedProductIDs.isEmpty))
        items.append(.divider("bulk-destructive-divider"))
        items.append(.action("delete", "Delete", systemImage: "trash", isDestructive: true, isDisabled: selectedProductIDs.isEmpty))
        return items
    }

    private func handleBulkSelectionAction(_ item: DSDropdownActionItem) {
        switch item.id {
        case "share":
            let selected = session.products.filter { selectedProductIDs.contains($0.id) }
            openShareDialog(for: selected)
        case "add-folder":
            guard !selectedProductIDs.isEmpty else { return }
            InteractionHaptics.tap(vibrate: session.vibrateEnabled)
            showAddToFolderSheet = true
        case "enhance":
            session.reprocessProducts(ids: selectedProductIDs)
        case "match-look":
            let ordered = session.products.filter { selectedProductIDs.contains($0.id) && !$0.isCompositeBundle }
            guard ordered.count >= 2, let source = ordered.first else { return }
            syncLookSource = source
            showSyncLookSheet = true
        case "reset":
            showBulkResetConfirm = true
        case "hide-brand-mark":
            session.setSuppressBrandMark(true, forIDs: selectedProductIDs)
        case "show-brand-mark":
            session.setSuppressBrandMark(false, forIDs: selectedProductIDs)
        case "delete":
            showBulkDeleteConfirm = true
        default:
            break
        }
    }

    private func proceedToGroupedCoverEditor() {
        groupedCoverEditingProductID = nil
        groupedCoverExistingLayout = nil
        showGroupedCoverNamePrompt = false
        showGroupedCoverEditor = true
    }

    private var groupedCoverNameEntrySheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.section) {
                    VStack(alignment: .leading, spacing: DS.Space.stack) {
                        Text("Cover name")
                            .font(DS.TypeScale.caption.weight(.semibold))
                            .foregroundStyle(DS.ColorToken.secondaryLabel)

                        TextField("Custom cover name", text: $groupedCoverNameText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .dsSemanticTextField()
                            .foregroundStyle(DS.ColorToken.label)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 11)
                            .background(
                                DS.ColorToken.backgroundTertiary,
                                in: RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                                    .stroke(DS.ColorToken.separator, lineWidth: 1)
                            )

                        Text("Used in the queue and exported filenames.")
                            .font(DS.TypeScale.caption)
                            .foregroundStyle(DS.ColorToken.secondaryLabel)
                    }

                    Button {
                        groupedCoverNameText = FileNameRules.generatedGroupedCoverName()
                        proceedToGroupedCoverEditor()
                    } label: {
                        Label("Use auto name (PS_CoverPhoto…)", systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    if groupedCoverNamePromptError {
                        Text("Enter a custom name or use the auto name option.")
                            .font(DS.TypeScale.caption)
                            .foregroundStyle(DS.ColorToken.error)
                    }
                }
                .padding(DS.Space.screenHorizontal)
                .padding(.vertical, DS.Space.screenVertical)
            }
            .background(DS.ColorToken.background)
            .navigationTitle("Name grouped cover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        groupedCoverNameText = ""
                        groupedCoverNamePromptError = false
                        showGroupedCoverNamePrompt = false
                    }
                    .foregroundStyle(DS.ColorToken.accent)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue") {
                        let trimmed = groupedCoverNameText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else {
                            groupedCoverNamePromptError = true
                            return
                        }
                        groupedCoverNameText = trimmed
                        groupedCoverNamePromptError = false
                        proceedToGroupedCoverEditor()
                    }
                    .foregroundStyle(DS.ColorToken.accent)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(DS.ColorToken.background)
    }

    private func enterSelectionMode(selecting product: CapturedProduct) {
        InteractionHaptics.selection(vibrate: session.vibrateEnabled)
        if !isSelectionMode { isSelectionMode = true }
        selectedProductIDs.insert(product.id)
    }

    private func queueRow(_ product: CapturedProduct) -> some View {
        let selected = isSelectionMode && selectedProductIDs.contains(product.id)
        let thumbSide: CGFloat = 56
        return DSListRowCard(isSelected: selected, compact: true) {
        HStack(alignment: .center, spacing: 6) {
            Text("\(displayNumber(for: product))")
                .font(DS.TypeScale.micro.weight(.bold))
                .foregroundStyle(DS.ColorToken.label)
                .monospacedDigit()
                .frame(width: 22, height: 22)
                .background(DS.ColorToken.backgroundTertiary)
                .clipShape(Circle())
                .overlay(Circle().stroke(DS.ColorToken.separator, lineWidth: 1))

            if isSelectionMode {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(selected ? DS.ColorToken.accent : DS.ColorToken.tertiaryLabel)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 22)
            }

            AsyncQueueRowThumbnail(productID: product.id, image: product.image, side: thumbSide)
                .overlay(alignment: .topTrailing) {
                    if let issue = product.queueQualityIssues.first {
                        Image(systemName: issue.symbolName)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(PSDesignColors.warning)
                            .padding(3)
                            .background(Circle().fill(PSDesignColors.background))
                            .offset(x: 4, y: -4)
                            .accessibilityLabel(issue.accessibilityLabel)
                    }
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(product.filename)
                        .font(DS.TypeScale.rowTitle.weight(.semibold))
                        .foregroundStyle(DS.ColorToken.label)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .multilineTextAlignment(.leading)
                    if product.angle != .none {
                        Text(product.angle.badgeTitle)
                            .font(DS.TypeScale.micro.weight(.semibold))
                            .foregroundStyle(DS.ColorToken.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(DS.ColorToken.accent.opacity(0.12), in: Capsule())
                    }
                }

                Text(queueSubtitle(for: product))
                    .font(DS.TypeScale.caption)
                    .foregroundStyle(DS.ColorToken.secondaryLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            DSDropdownActionMenu(
                label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DS.ColorToken.label)
                        .frame(width: 30, height: 30)
                        .background(DS.ColorToken.backgroundTertiary)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(DS.ColorToken.separator, lineWidth: 1))
                },
                items: queueRowActionItems(for: product)
            ) { item in
                handleQueueRowAction(item, product: product)
            }
            .buttonStyle(.plainPressable)
            .opacity(isSelectionMode ? 0 : 1)
            .allowsHitTesting(!isSelectionMode)
            .accessibilityHidden(isSelectionMode)
        }
        .contentShape(Rectangle())
        }
    }

    private func queueRowActionItems(for product: CapturedProduct) -> [DSDropdownActionItem] {
        var items: [DSDropdownActionItem] = [
            .header("OPEN / EDIT"),
            .action("preview", "Preview"),
            .action("rename", "Edit Name"),
            .action("replace", "Replace"),
            .header("QUICK PROCESSING"),
            .action("standard-clean", "Standard Clean"),
            .action("defringe", "Fix edges (de-fringe)"),
            .header("OUTPUT"),
            .action("share", "Export…", systemImage: "square.and.arrow.up"),
        ]
        if session.brandMarkEnabled {
            items.append(.header("BRAND KIT"))
            items.append(.action(
                "hide-brand-mark",
                "Hide Brand Mark",
                systemImage: "seal.slash",
                isSelected: product.suppressBrandMark
            ))
        }
        items.append(.header("DESTRUCTIVE"))
        items.append(.action("delete", "Delete", systemImage: "trash", isDestructive: true))
        return items
    }

    private func handleQueueRowAction(_ item: DSDropdownActionItem, product: CapturedProduct) {
        switch item.id {
        case "preview":
            previewIndex = indexOf(product)
        case "rename":
            startRename(product)
        case "share":
            openShareDialog(for: [product])
        case "defringe":
            session.applyDefringeSharpen(to: product)
        case "standard-clean":
            quickApply(product, mode: .standardClean, strength: CatalogProcessingBaseline.strength)
        case "hide-brand-mark":
            session.setSuppressBrandMark(!product.suppressBrandMark, for: product)
        case "replace":
            startReplace(product)
        case "delete":
            session.remove(product)
        default:
            break
        }
    }

    private func queueSubtitle(for product: CapturedProduct) -> String {
        let captured = product.capturedAt.formatted(date: .abbreviated, time: .shortened)
        return "\(captured) · \(product.canvasWidth)×\(product.canvasHeight)"
    }


    private func queueRowWithActions(_ product: CapturedProduct) -> some View {
        queueRow(product)
            .contentShape(Rectangle())
            .gesture(
                LongPressGesture(minimumDuration: 0.35)
                    .onEnded { _ in
                        enterSelectionMode(selecting: product)
                    }
                    .exclusively(before: TapGesture().onEnded {
                        if isSelectionMode {
                            toggleSelection(product)
                        } else {
                            previewIndex = indexOf(product)
                        }
                    })
            )
            .listRowInsets(.init(top: 2, leading: AppLayout.listRowInsetH, bottom: 2, trailing: AppLayout.listRowInsetH))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .modifier(QueueTrailingSwipeActions(
                enabled: !isSelectionMode,
                onDelete: { session.remove(product) },
                onReplace: { startReplace(product) },
                onRename: { startRename(product) },
                onEnhance: { session.reprocessProduct(product) }
            ))
            .modifier(QueueLeadingSwipeActions(
                enabled: !isSelectionMode,
                onShare: { openShareDialog(for: [product]) },
                onView: { previewIndex = indexOf(product) }
            ))
    }

    private func toggleSelection(_ product: CapturedProduct) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if selectedProductIDs.contains(product.id) {
                selectedProductIDs.remove(product.id)
            } else {
                selectedProductIDs.insert(product.id)
            }
        }
    }

    private func clearExportUIState() {
        loadingState.endActions(prefix: "export-")
    }

    private func indexOf(_ product: CapturedProduct) -> Int { session.products.firstIndex(where: { $0.id == product.id }) ?? 0 }
    private func displayNumber(for product: CapturedProduct) -> Int { (filteredProducts.firstIndex(where: { $0.id == product.id }) ?? 0) + 1 }

    private func startRename(_ product: CapturedProduct) {
        renamingProduct = product
        renameText = product.upc
    }

    private func quickApply(_ product: CapturedProduct, mode: PhotoEnhancementMode, strength: StudioAIStrength) {
        session.reprocessProduct(
            product,
            removeBackground: product.backgroundRemoved || session.autoBackgroundRemoval,
            polishEnabled: true,
            enhancementMode: mode,
            studioAIStrength: strength,
            canvasWidth: product.canvasWidth,
            canvasHeight: product.canvasHeight,
            fillRatio: product.fillRatio,
            backgroundColor: product.backgroundColor,
            secondaryBackgroundColor: product.secondaryBackgroundColor,
            backgroundStyle: product.backgroundStyle,
            gradientColorHexes: product.gradientColorHexes
        )
    }

    @ViewBuilder
    private var exportButtons: some View {
        let isExporting = loadingState.isAnyRunning(prefix: "export-")
        HStack(spacing: DS.Space.stack) {
            if isSelectionMode {
                Button {
                    guard !isExporting else { return }
                    openShareDialog(for: bulkShareTargets)
                } label: {
                    HStack(spacing: 6) {
                        if isExporting {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(DS.ColorToken.onAccent)
                                .scaleEffect(0.8)
                        }
                        Text(isExporting ? "Exporting…" : primaryExportButtonTitle)
                    }
                }
                .buttonStyle(CompactPrimaryButtonStyle())
                .disabled(session.products.isEmpty || isExporting)
                .opacity(session.products.isEmpty || isExporting ? DS.Motion.disabledOpacity : 1)

                Button("Delete") { showBulkDeleteConfirm = true }
                    .buttonStyle(CompactDangerButtonStyle())
                    .disabled(selectedProductIDs.isEmpty || isExporting)
            } else {
                Button {
                    guard !isExporting else { return }
                    openShareDialog(for: bulkShareTargets)
                } label: {
                    HStack(spacing: 8) {
                        if isExporting {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(DS.ColorToken.onAccent)
                                .scaleEffect(0.85)
                        }
                        Text(isExporting ? "Exporting…" : primaryExportButtonTitle)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(session.products.isEmpty || isExporting)
                .opacity(session.products.isEmpty || isExporting ? DS.Motion.disabledOpacity : 1)

                Button("Clear") { showClearConfirm = true }
                    .buttonStyle(DangerButtonStyle())
                    .disabled(session.products.isEmpty || isExporting)
                    .frame(maxWidth: 120)
            }
        }
        .frame(minHeight: 47)
    }

    private var primaryExportButtonTitle: String {
        let n = bulkShareTargets.count
        if isSelectionMode, !selectedProductIDs.isEmpty {
            return "Export Selected (\(n))"
        }
        return "Export Queue"
    }

    private func share(products: [CapturedProduct], includeCSV: Bool, format: ExportImageFormat) {
        let ids = products.map(\.id)
        let namingMode = session.imageNamingMode
        let quality = session.compressBeforeShare ? session.jpegQuality : 1.0
        let marketplace = MarketplaceExportProfileID.from(exportChannel: session.exportChannelProfile)
        let metadataSnapshot = session.metadataManager.exportSnapshot()
        let brandName = session.brandMarkText
        loadingState.runAction(key: "export-share", message: "Exporting…", global: true, vibrate: session.vibrateEnabled) {
            let urls = await Task.detached(priority: .userInitiated) {
                ExportManager.exportURLs(
                    for: products,
                    namingMode: namingMode,
                    includeCSV: includeCSV,
                    quality: quality,
                    format: format,
                    marketplaceProfile: marketplace,
                    brandName: brandName,
                    metadataSnapshot: metadataSnapshot
                )
            }.value
            guard !urls.isEmpty else { return }
            await MainActor.run {
                session.metadataManager.recordExport(
                    productIDs: ids,
                    format: format.fileExtension.uppercased(),
                    marketplace: marketplace.displayName
                )
                sharePayload = SharePayload(items: urls, productIDsForRemovalPrompt: ids)
            }
        }
    }

    private func shareAllFormats(products: [CapturedProduct]) {
        let ids = products.map(\.id)
        let namingMode = session.imageNamingMode
        let quality = session.compressBeforeShare ? session.jpegQuality : 1.0
        loadingState.runAction(key: "export-all-formats", message: "Exporting…", global: true, vibrate: session.vibrateEnabled) {
            let urls = await Task.detached(priority: .userInitiated) {
                ExportManager.exportAllFormatsURLs(
                    for: products,
                    namingMode: namingMode,
                    includeCSV: true,
                    quality: quality
                )
            }.value
            guard !urls.isEmpty else { return }
            await MainActor.run {
                sharePayload = SharePayload(items: urls, productIDsForRemovalPrompt: ids)
            }
        }
    }

    private func shareCSVOnly(products: [CapturedProduct]) {
        let ids = products.map(\.id)
        let namingMode = session.imageNamingMode
        let marketplace = MarketplaceExportProfileID.from(exportChannel: session.exportChannelProfile)
        let metadataSnapshot = session.metadataManager.exportSnapshot()
        let brandName = session.brandMarkText
        loadingState.runAction(key: "export-csv", message: "Exporting…", global: true, vibrate: session.vibrateEnabled) {
            let csv = await Task.detached(priority: .userInitiated) {
                ExportManager.csvURL(
                    for: products,
                    namingMode: namingMode,
                    marketplaceProfile: marketplace,
                    brandName: brandName,
                    metadataSnapshot: metadataSnapshot
                )
            }.value
            guard let csv else { return }
            await MainActor.run {
                session.metadataManager.recordExport(
                    productIDs: ids,
                    format: "CSV",
                    marketplace: marketplace.displayName,
                    packageFilename: CSVExporter.legacyManifestFilename
                )
                sharePayload = SharePayload(items: [csv], productIDsForRemovalPrompt: ids)
            }
        }
    }

    private func shareZip(products: [CapturedProduct], includeCSV: Bool) {
        _ = includeCSV // Package always includes products.csv + manifest.json.
        let ids = products.map(\.id)
        let q = session.compressBeforeShare ? session.jpegQuality : 1.0
        let namingMode = session.imageNamingMode
        let marketplace = MarketplaceExportProfileID.from(exportChannel: session.exportChannelProfile)
        let metadataSnapshot = session.metadataManager.exportSnapshot()
        let context = ExportPackageContext(
            projectName: session.activeCatalogSessionName,
            marketplaceProfile: marketplace,
            brandName: session.brandMarkText,
            namingMode: namingMode,
            jpegQuality: q,
            metadataSnapshot: metadataSnapshot
        )
        loadingState.runAction(key: "export-zip", message: "Building ZIP…", global: true, vibrate: session.vibrateEnabled) {
            let url = await Task.detached(priority: .userInitiated) {
                ExportManager.zipExportURL(for: products, context: context)
            }.value
            guard let url else { return }
            await MainActor.run {
                session.metadataManager.recordExport(
                    productIDs: ids,
                    format: "ZIP",
                    marketplace: marketplace.displayName,
                    packageFilename: url.lastPathComponent
                )
                sharePayload = SharePayload(items: [url], productIDsForRemovalPrompt: ids)
            }
        }
    }

    private func startReplace(_ product: CapturedProduct) {
        replacingProduct = product
        showReplaceCamera = true
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, !urls.isEmpty else { return }
        let gate = session.gateAddingPhotos(count: urls.count)
        if gate.isBlocked {
            loadingState.showToast(gate.userMessage, isError: true)
            return
        }
        startImportProgress(total: urls.count)
        Task {
            await MainActor.run { session.beginSessionPersistenceBatch() }
            _ = await session.streamImportCatalogImages(
                total: urls.count,
                progressMessage: "Importing from Files…"
            ) { index in
                guard index >= 0, index < urls.count else { return nil }
                let url = urls[index]
                let allowed = url.startAccessingSecurityScopedResource()
                defer { if allowed { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else { return nil }
                return autoreleasepool { ImageImportDecoder.uiImage(from: data) ?? UIImage(data: data) }
            }
            await MainActor.run {
                session.endSessionPersistenceBatch()
                finishImportProgress()
            }
        }
    }

    private func importSelectedPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        let gate = session.gateAddingPhotos(count: items.count)
        if gate.isBlocked {
            selectedPhotoItems = []
            loadingState.showToast(gate.userMessage, isError: true)
            return
        }
        startImportProgress(total: items.count)
        Task {
            await MainActor.run { session.beginSessionPersistenceBatch() }
            _ = await session.streamImportCatalogImages(
                total: items.count,
                progressMessage: "Importing from Photos…"
            ) { index in
                guard index >= 0, index < items.count else { return nil }
                guard let data = try? await items[index].loadTransferable(type: Data.self) else { return nil }
                return autoreleasepool { ImageImportDecoder.uiImage(from: data) ?? UIImage(data: data) }
            }
            await MainActor.run {
                session.endSessionPersistenceBatch()
                selectedPhotoItems = []
                finishImportProgress()
            }
        }
    }

    private func startImportProgress(total: Int) {
        session.updateActiveImport(completed: 0, total: total, message: "Preparing import…")
    }

    private func finishImportProgress() {
        session.clearActiveImport()
    }

    private var emptyState: some View {
        DSCard(padding: DS.Space.screenVertical) {
            VStack(spacing: DS.Space.section) {
                ZStack {
                    Circle()
                        .fill(DS.ColorToken.backgroundTertiary)
                        .frame(width: 88, height: 88)
                        .overlay(Circle().stroke(DS.ColorToken.separator, lineWidth: 1))
                    Image(systemName: "square.stack.3d.up.slash")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(DS.ColorToken.accent)
                }
                Text(
                    emptyStateTitle
                )
                    .font(DS.TypeScale.sectionTitle)
                    .foregroundStyle(DS.ColorToken.label)
                Text(emptyStateDetail)
                    .font(DS.TypeScale.body)
                    .foregroundStyle(DS.ColorToken.secondaryLabel)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateTitle: String {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No matches found"
        }
        switch queueFilter {
        case .all: return "No products queued yet"
        case .ready: return "No ready images"
        case .attention: return "Nothing needs attention"
        case .edited: return "No edited images"
        }
    }

    private var emptyStateDetail: String {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Try a different filename or UPC search term."
        }
        switch queueFilter {
        case .all:
            return "Import from Photos or Files, or capture new photos. New items appear at the top of this queue."
        case .ready:
            return "Images without quality attention issues appear here."
        case .attention:
            return "Images with quality attention issues will appear here when flags are available."
        case .edited:
            return "Images you edit in preview will appear in this filter."
        }
    }

    private var filteredProducts: [CapturedProduct] {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let searched = session.products.filter { product in
            guard !term.isEmpty else { return true }
            return product.filename.lowercased().contains(term) || product.upc.lowercased().contains(term)
        }
        let filtered = queueFilter.filtered(searched)
        return sortOption.sorted(filtered)
    }

    private struct UPCQueueSection: Identifiable {
        var id: String { upc }
        let upc: String
        let products: [CapturedProduct]
    }

    private var upcGroupedSections: [UPCQueueSection] {
        let products = filteredProducts
        let grouped = Dictionary(grouping: products, by: \.upc)
        let sections: [UPCQueueSection] = grouped.map { key, items in
            let ordered = items.sorted { a, b in
                if a.multiAngleOrdinal != b.multiAngleOrdinal {
                    let ao = a.multiAngleOrdinal == 0 ? Int.max : a.multiAngleOrdinal
                    let bo = b.multiAngleOrdinal == 0 ? Int.max : b.multiAngleOrdinal
                    if ao != bo { return ao < bo }
                }
                let ai = ProductAngle.captureAngles.firstIndex(of: a.angle) ?? Int.max
                let bi = ProductAngle.captureAngles.firstIndex(of: b.angle) ?? Int.max
                if ai != bi { return ai < bi }
                return a.capturedAt > b.capturedAt
            }
            return UPCQueueSection(upc: key, products: ordered)
        }
        return sections.sorted { a, b in
            let da = a.products.map(\.capturedAt).max() ?? .distantPast
            let db = b.products.map(\.capturedAt).max() ?? .distantPast
            return da > db
        }
    }
}

private enum ShareCSVFormatAsk {
    case jpg([CapturedProduct])
    case png([CapturedProduct])

    var products: [CapturedProduct] {
        switch self {
        case .jpg(let p), .png(let p): return p
        }
    }

    var format: ExportImageFormat {
        switch self {
        case .jpg: return .jpg
        case .png: return .png
        }
    }
}

enum PreviewShareCSVAsk: Equatable {
    case jpg
    case png

    var format: ExportImageFormat {
        switch self {
        case .jpg: return .jpg
        case .png: return .png
        }
    }
}

private enum QueueSortOption: String, CaseIterable, Identifiable {
    case newestFirst = "Newest First"
    case oldestFirst = "Oldest First"
    case nameAToZ = "Name A-Z"

    var id: String { rawValue }

    func sorted(_ products: [CapturedProduct]) -> [CapturedProduct] {
        switch self {
        case .newestFirst:
            return products.sorted { $0.capturedAt > $1.capturedAt }
        case .oldestFirst:
            return products.sorted { $0.capturedAt < $1.capturedAt }
        case .nameAToZ:
            return products.sorted { $0.filename.localizedCaseInsensitiveCompare($1.filename) == .orderedAscending }
        }
    }
}


private struct QueueTrailingSwipeActions: ViewModifier {
    var enabled: Bool = true
    let onDelete: () -> Void
    let onReplace: () -> Void
    let onRename: () -> Void
    let onEnhance: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive, action: onDelete) { Text("Delete") }
                Button(action: onReplace) { Text("Replace") }.tint(.orange)
                Button(action: onRename) { Text("Rename") }.tint(AppTheme.primary)
                Button(action: onEnhance) { Label("Enhance", systemImage: "sparkles") }.tint(.purple)
            }
        } else {
            content
        }
    }
}

private struct QueueLeadingSwipeActions: ViewModifier {
    var enabled: Bool = true
    let onShare: () -> Void
    let onView: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button(action: onShare) { Text("Share") }.tint(.blue)
                Button(action: onView) { Text("View") }.tint(.gray)
            }
        } else {
            content
        }
    }
}

