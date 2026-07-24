import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Unsaved changes (SwiftUI)

private enum UnsavedLeaveIntent {
    case back
    case dismiss
}

private struct UnsavedChangesConfirmationModifier: ViewModifier {
    @Binding var isPresented: Bool
    var title: String = "Unsaved changes"
    var message: String
    let onSave: () -> Void
    let onDiscard: () -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(title, isPresented: $isPresented, titleVisibility: .visible) {
            Button("Keep Editing", role: .cancel) {}
            Button("Discard", role: .destructive, action: onDiscard)
            Button("Save", action: onSave)
        } message: {
            Text(message)
        }
    }
}

private extension View {
    func unsavedChangesConfirmation(
        isPresented: Binding<Bool>,
        title: String = "Unsaved changes",
        message: String,
        onSave: @escaping () -> Void,
        onDiscard: @escaping () -> Void
    ) -> some View {
        modifier(UnsavedChangesConfirmationModifier(
            isPresented: isPresented,
            title: title,
            message: message,
            onSave: onSave,
            onDiscard: onDiscard
        ))
    }
}

// MARK: - Library browse tabs

enum ImageBackgroundBrowseTab: String, CaseIterable, Identifiable {
    case online = "Online"
    case sources = "Sources"
    case library = "Library"

    var id: String { rawValue }
}

private enum LibraryFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case online = "From Online"
    case favorites = "Favorites"
    case recent = "Recent"
    case imported = "Imported"

    var id: String { rawValue }
}

// MARK: - Image Background child sheet

struct ImageBackgroundPickerSheet: View {
    @Binding var spec: BackgroundFillSpec
    @Binding var selectedCategory: ImageBackgroundCategory
    var presetScrollRequestID: UUID
    var canvasWidth: Int
    var canvasHeight: Int
    var fillRatio: Double
    var cutoutSize: CGSize
    var onCaptureUndo: () -> Void
    var onLiveSpecChange: () -> Void
    var onSpecChange: () -> Void
    var onDismiss: () -> Void
    var initialBrowseTab: ImageBackgroundBrowseTab = .library

    @Environment(\.dismiss) private var dismiss

    @State private var browseTab: ImageBackgroundBrowseTab = .library
    @State private var libraryFilter: LibraryFilter = .all

    @State private var showPhotoPicker = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showFileImporter = false
    @State private var urlText = ""
    @State private var importError: String?
    @State private var isImporting = false
    @State private var didCapturePickerUndo = false
    @State private var baselineSpec: BackgroundFillSpec?
    @State private var showLeaveConfirmation = false
    @State private var pendingLeaveIntent: UnsavedLeaveIntent = .back

    @State private var onlineQuery = ""
    @State private var selectedChipID: String? = OnlineBackgroundService.collectionChips.first?.id
    @State private var onlineResults: [OnlineBackgroundService.SearchResult] = []
    @State private var isSearchingOnline = false
    @State private var onlineError: String?
    @State private var downloadingResultID: String?
    @State private var searchTask: Task<Void, Never>?

    private var activeBackgroundID: String? {
        spec.imageSelection?.backgroundID
    }

    private var essentialItems: [ImageBackgroundListItem] {
        ImageBackgroundFolderCatalog.essentialDefinitions.map { ImageBackgroundListItem.bundled($0) }
    }

    private var libraryItems: [ImageBackgroundListItem] {
        switch libraryFilter {
        case .all:
            return ImageBackgroundStore.shared.allRecords.map { ImageBackgroundListItem.custom($0) }
        case .online:
            return ImageBackgroundStore.shared.records(for: .online).map { ImageBackgroundListItem.custom($0) }
        case .favorites:
            return ImageBackgroundFolderCatalog.listItems(for: ImageBackgroundFavoritesStore.favoriteIDs)
        case .recent:
            let storeRecent = ImageBackgroundStore.shared.recentIDs.compactMap { ImageBackgroundStore.shared.record(id: $0) }
            if !storeRecent.isEmpty {
                return storeRecent.map { ImageBackgroundListItem.custom($0) }
            }
            return ImageBackgroundFolderCatalog.listItems(for: ImageBackgroundRecentStore.ids)
        case .imported:
            return ImageBackgroundStore.shared.allRecords
                .filter { $0.source != .online && $0.source != .bundled }
                .map { ImageBackgroundListItem.custom($0) }
        }
    }

    private var hasUnsavedPickerChanges: Bool {
        guard let baselineSpec else { return false }
        return spec != baselineSpec
    }

    private var activeSearchQuery: String {
        let typed = onlineQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty {
            return OnlineBackgroundService.backgroundBiasedQuery(typed)
        }
        if let chip = OnlineBackgroundService.collectionChips.first(where: { $0.id == selectedChipID }) {
            return chip.query
        }
        return OnlineBackgroundService.collectionChips.first?.query
            ?? OnlineBackgroundService.backgroundBiasedQuery("studio")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.tight) {
                    browseTabPicker
                    switch browseTab {
                    case .online:
                        onlineSection
                    case .sources:
                        sourcesSection
                    case .library:
                        librarySection
                    }
                }
                .padding(.horizontal, DS.Space.cardPadding)
                .padding(.bottom, 24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back") { requestLeave(.back) }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DS.ColorToken.accent)
                }
                .dsHideToolbarSharedBackground()
                ToolbarItem(placement: .principal) {
                    Text("Image Background")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DS.ColorToken.label)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { saveAndDismiss() }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DS.ColorToken.accent)
                }
                .dsHideToolbarSharedBackground()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .interactiveDismissDisabled(hasUnsavedPickerChanges)
        .onAppear {
            browseTab = initialBrowseTab
            baselineSpec = spec
            if browseTab == .online {
                runOnlineSearch()
            }
        }
        .onDisappear { searchTask?.cancel() }
        .unsavedChangesConfirmation(
            isPresented: $showLeaveConfirmation,
            message: "Save your background choice, discard your edits, or keep editing.",
            onSave: { saveAndDismiss() },
            onDiscard: { discardAndDismiss() }
        )
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItems, maxSelectionCount: 1, matching: .images)
        .onChange(of: selectedPhotoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await importPhotos(items) }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
            handleFileImport(result)
        }
    }

    // MARK: - Browse tabs

    private var browseTabPicker: some View {
        Picker("Browse", selection: $browseTab) {
            ForEach(ImageBackgroundBrowseTab.allCases) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: browseTab) { _, tab in
            if tab == .online, onlineResults.isEmpty, !isSearchingOnline {
                runOnlineSearch()
            }
        }
    }

    // MARK: - Online

    private var onlineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(DS.ColorToken.secondaryLabel)
                TextField("Search backgrounds", text: $onlineQuery)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .dsSemanticTextField()
                    .onSubmit { selectedChipID = nil; runOnlineSearch() }
                if !onlineQuery.isEmpty {
                    Button {
                        onlineQuery = ""
                        runOnlineSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(DS.ColorToken.secondaryLabel)
                    }
                    .buttonStyle(.plain)
                }
                Button("Search") {
                    selectedChipID = nil
                    runOnlineSearch()
                }
                .font(.system(size: 13, weight: .semibold))
                .disabled(isSearchingOnline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(DS.ColorToken.backgroundTertiary, in: RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous).stroke(DS.ColorToken.separator, lineWidth: 1))

            onlineChipRow

            if !OnlineBackgroundService.isConfigured {
                Text(OnlineBackgroundService.ServiceError.missingAPIKey.errorDescription ?? "")
                    .font(DS.TypeScale.micro)
                    .foregroundStyle(DS.ColorToken.secondaryLabel)
                    .padding(.vertical, 4)
            }

            if isSearchingOnline && onlineResults.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Searching free stock…")
                        .font(DS.TypeScale.micro)
                        .foregroundStyle(DS.ColorToken.secondaryLabel)
                }
                .padding(.vertical, 12)
            } else if let onlineError {
                Text(onlineError)
                    .font(DS.TypeScale.micro)
                    .foregroundStyle(.red.opacity(0.85))
            } else if onlineResults.isEmpty {
                Text("No results. Try another search.")
                    .font(DS.TypeScale.micro)
                    .foregroundStyle(DS.ColorToken.secondaryLabel)
                    .padding(.vertical, 8)
            } else {
                onlineResultsGrid
                    .padding(.top, 2)
            }

            Text(OnlineBackgroundService.attributionFooter)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DS.ColorToken.secondaryLabel)
        }
    }

    /// Horizontal tags in a fixed-height row so taps don’t fall through to result cells below.
    private var onlineChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(OnlineBackgroundService.collectionChips) { chip in
                    let selected = selectedChipID == chip.id
                        && onlineQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    Button {
                        InteractionHaptics.selection()
                        onlineQuery = ""
                        selectedChipID = chip.id
                        runOnlineSearch()
                    } label: {
                        Text(chip.title)
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .foregroundStyle(selected ? Color.white : DS.ColorToken.label)
                            .background(selected ? DS.ColorToken.accent : DS.ColorToken.backgroundTertiary, in: Capsule())
                            .overlay(Capsule().stroke(DS.ColorToken.separator, lineWidth: selected ? 0 : 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.vertical, 2)
        }
        .frame(height: 40)
        .contentShape(Rectangle())
        .zIndex(2)
    }

    private var onlineResultsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 10) {
            ForEach(onlineResults) { result in
                onlineResultCell(result)
            }
        }
    }

    private func onlineResultCell(_ result: OnlineBackgroundService.SearchResult) -> some View {
        let isDownloading = downloadingResultID == result.id
        return Button {
            Task { await selectOnlineResult(result) }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                ZStack {
                    OnlineRemoteThumb(url: result.thumbURL)
                        .frame(maxWidth: .infinity)
                        .frame(height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    if isDownloading {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.black.opacity(0.35))
                        ProgressView().tint(.white)
                    }
                }
                Text(result.attributionLine)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(DS.ColorToken.secondaryLabel)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plainPressable)
        .disabled(isDownloading || downloadingResultID != nil)
    }

    // MARK: - Sources

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            localGridSection(
                title: "Essentials",
                items: essentialItems,
                empty: "No essential backgrounds bundled."
            )
            importSection
        }
    }

    // MARK: - Library

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(LibraryFilter.allCases) { filter in
                        let selected = libraryFilter == filter
                        Button {
                            libraryFilter = filter
                        } label: {
                            Text(filter.rawValue)
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .foregroundStyle(selected ? Color.white : DS.ColorToken.label)
                                .background(selected ? DS.ColorToken.accent : DS.ColorToken.backgroundTertiary, in: Capsule())
                                .overlay(Capsule().stroke(DS.ColorToken.separator, lineWidth: selected ? 0 : 1))
                        }
                        .buttonStyle(.plainPressable)
                    }
                }
            }
            localGridSection(title: "Library", items: libraryItems, empty: libraryEmptyMessage)
        }
    }

    private var libraryEmptyMessage: String {
        switch libraryFilter {
        case .all: return "Saved online and imported backgrounds appear here."
        case .online: return "Search Online and tap a background to save it here."
        case .favorites: return "Star backgrounds to save them here."
        case .recent: return "No recently used backgrounds yet."
        case .imported: return "Imports from Sources (Photos, Files, Clipboard, URL) appear here."
        }
    }

    private func localGridSection(title: String, items: [ImageBackgroundListItem], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel(title)
            if items.isEmpty {
                Text(empty)
                    .font(DS.TypeScale.micro)
                    .foregroundStyle(DS.ColorToken.secondaryLabel)
                    .padding(.vertical, 8)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 10) {
                    ForEach(items) { item in
                        localGridThumb(item)
                    }
                }
            }
        }
        .padding(8)
        .background(DS.ColorToken.backgroundTertiary.opacity(0.55), in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous).stroke(DS.ColorToken.separator, lineWidth: 1))
    }

    private func localGridThumb(_ item: ImageBackgroundListItem) -> some View {
        let selected = item.selectionBackgroundID == activeBackgroundID
            && item.customRef == spec.imageSelection?.customImageRef
        let isFavorite = ImageBackgroundFavoritesStore.isFavorite(item.selectionBackgroundID)
        return ZStack(alignment: .topTrailing) {
            Button {
                selectItem(item)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Image(uiImage: item.thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .frame(height: 64)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(selected ? DS.ColorToken.accent : DS.ColorToken.separator, lineWidth: selected ? 2.5 : 1)
                        )
                    Text(item.title)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(selected ? DS.ColorToken.accent : DS.ColorToken.label)
                        .lineLimit(1)
                    if let credit = item.attributionLine {
                        Text(credit)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(DS.ColorToken.secondaryLabel)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plainPressable)

            Button {
                InteractionHaptics.selection()
                ImageBackgroundFavoritesStore.toggleFavorite(item.selectionBackgroundID)
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isFavorite ? Color.yellow : DS.ColorToken.secondaryLabel)
                    .padding(6)
            }
            .buttonStyle(.plainPressable)
        }
    }

    // MARK: - Leave / save

    private func requestLeave(_ intent: UnsavedLeaveIntent) {
        guard hasUnsavedPickerChanges else {
            onDismiss()
            dismiss()
            return
        }
        pendingLeaveIntent = intent
        showLeaveConfirmation = true
    }

    private func saveAndDismiss() {
        onDismiss()
        dismiss()
    }

    private func discardAndDismiss() {
        if let baselineSpec {
            spec = baselineSpec
            onLiveSpecChange()
        }
        onDismiss()
        dismiss()
    }

    // MARK: - Import (Sources tab only)

    private var importSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("From your device")
            VStack(spacing: 8) {
                importRow(title: "Photos", icon: "photo.on.rectangle") {
                    showPhotoPicker = true
                }
                importRow(title: "Files", icon: "folder") {
                    showFileImporter = true
                }
                importRow(title: "Clipboard", icon: "doc.on.clipboard") {
                    importFromClipboard()
                }
                urlImportRow
            }
            if isImporting {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Importing image…")
                        .font(DS.TypeScale.micro)
                        .foregroundStyle(DS.ColorToken.secondaryLabel)
                }
            }
            if let importError {
                Text(importError)
                    .font(DS.TypeScale.micro)
                    .foregroundStyle(.red.opacity(0.85))
            }
        }
    }

    private func importRow(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button {
            InteractionHaptics.tap()
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 22)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.ColorToken.secondaryLabel)
            }
            .foregroundStyle(DS.ColorToken.label)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(DS.ColorToken.backgroundTertiary, in: RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous).stroke(DS.ColorToken.separator, lineWidth: 1))
        }
        .buttonStyle(GlassPreviewButtonStyle())
        .disabled(isImporting)
    }

    private var urlImportRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 22)
                TextField("Image URL", text: $urlText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .dsSemanticTextField()
                Button("Import") {
                    InteractionHaptics.tap()
                    Task { await importFromURL() }
                }
                .font(.system(size: 12, weight: .semibold))
                .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isImporting)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(DS.ColorToken.backgroundTertiary, in: RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous).stroke(DS.ColorToken.separator, lineWidth: 1))
        }
    }

    // MARK: - Actions

    private func captureUndoIfNeeded() {
        guard !didCapturePickerUndo else { return }
        didCapturePickerUndo = true
        onCaptureUndo()
    }

    private func selectItem(_ item: ImageBackgroundListItem) {
        InteractionHaptics.selection()
        captureUndoIfNeeded()
        let definition = item.definition
        let canvasSize = CGSize(width: CGFloat(max(canvasWidth, 1)), height: CGFloat(max(canvasHeight, 1)))
        let placementFillRatio = item.isOnlineBackground
            ? ImageBackgroundAutoPlacement.onlineBackgroundFillRatio
            : fillRatio
        mutateSpec(commit: false) { s in
            s.fillKind = .image
            var selection = ImageBackgroundSelection(
                backgroundID: item.selectionBackgroundID,
                customImageRef: item.customRef,
                shadow: s.imageSelection?.shadow ?? .off
            )
            ImageBackgroundAutoPlacement.applyAutoPlacement(
                to: &selection,
                definition: definition,
                cutoutSize: cutoutSize,
                canvasSize: canvasSize,
                fillRatio: placementFillRatio
            )
            s.imageSelection = selection
            s.normalizeImageSelection()
        }
        ImageBackgroundRecentStore.markUsed(item.selectionBackgroundID)
        if let ref = item.customRef {
            ImageBackgroundStore.shared.markRecentlyUsed(ref)
        }
        onLiveSpecChange()
    }

    private func mutateSpec(commit: Bool, _ edit: (inout BackgroundFillSpec) -> Void) {
        var next = spec
        edit(&next)
        spec = next
        if commit { onSpecChange() } else { onLiveSpecChange() }
    }

    private func runOnlineSearch() {
        searchTask?.cancel()
        let query = activeSearchQuery
        isSearchingOnline = true
        onlineError = nil
        searchTask = Task {
            do {
                let results = try await OnlineBackgroundService.search(query: query)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    onlineResults = results
                    isSearchingOnline = false
                    onlineError = nil
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    onlineResults = []
                    isSearchingOnline = false
                    onlineError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }

    private func selectOnlineResult(_ result: OnlineBackgroundService.SearchResult) async {
        await MainActor.run {
            downloadingResultID = result.id
            onlineError = nil
        }
        defer {
            Task { @MainActor in downloadingResultID = nil }
        }
        do {
            if let existing = ImageBackgroundStore.shared.record(provider: result.provider, photoID: result.providerPhotoID) {
                await MainActor.run {
                    browseTab = .library
                    libraryFilter = .online
                    selectItem(ImageBackgroundListItem.custom(existing))
                }
                return
            }
            let image = try await OnlineBackgroundService.downloadImage(from: result.downloadURL)
            let provenance = result.provenance()
            let record = try await MainActor.run {
                try ImageBackgroundStore.shared.importImage(
                    image,
                    source: .online,
                    title: result.title,
                    provenance: provenance
                )
            }
            await MainActor.run {
                browseTab = .library
                libraryFilter = .online
                selectItem(ImageBackgroundListItem.custom(record))
            }
        } catch {
            await MainActor.run {
                onlineError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func importFromClipboard() {
        importError = nil
        let snapshot = ClipboardURLImageImport.readClipboard()
        if let image = snapshot.images.first {
            importImage(image, source: .clipboard)
            return
        }
        if snapshot.images.isEmpty, let url = snapshot.urls.first {
            urlText = url.absoluteString
            Task { await importFromURL() }
            return
        }
        importError = ClipboardURLImageImportError.nothingToImport.localizedDescription
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        isImporting = true
        defer {
            isImporting = false
            selectedPhotoItems = []
        }
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = ImageImportDecoder.uiImage(from: data) else {
                await MainActor.run { importError = "Could not load the selected photo." }
                continue
            }
            await MainActor.run { importImage(image, source: .photos) }
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        importError = nil
        switch result {
        case .failure:
            importError = "Could not open the selected file."
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                importError = "Could not access the selected file."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let data = try? Data(contentsOf: url),
                  let image = ImageImportDecoder.uiImage(from: data) else {
                importError = "The file is not a supported image."
                return
            }
            importImage(image, source: .files, title: url.deletingPathExtension().lastPathComponent)
        }
    }

    private func importFromURL() async {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = ClipboardURLImageImport.parseURL(from: trimmed) else {
            await MainActor.run { importError = ClipboardURLImageImportError.invalidURL.localizedDescription }
            return
        }
        isImporting = true
        defer { isImporting = false }
        do {
            let image = try await ClipboardURLImageImport.downloadImage(from: url)
            await MainActor.run {
                importImage(image, source: .url, title: url.lastPathComponent)
                urlText = ""
            }
        } catch {
            await MainActor.run {
                importError = (error as? LocalizedError)?.errorDescription ?? "Download failed."
            }
        }
    }

    private func importImage(_ image: UIImage, source: ImageBackgroundSource, title: String? = nil) {
        importError = nil
        do {
            let record = try ImageBackgroundStore.shared.importImage(image, source: source, title: title)
            browseTab = .library
            libraryFilter = .imported
            let item = ImageBackgroundListItem.custom(record)
            selectItem(item)
        } catch {
            importError = error.localizedDescription
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(DS.TypeScale.dockSection)
            .foregroundStyle(DS.ColorToken.secondaryLabel)
    }
}

// MARK: - Remote thumb

private struct OnlineRemoteThumb: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(DS.ColorToken.backgroundTertiary)
                    .overlay(ProgressView().controlSize(.mini))
            }
        }
        .task(id: url) {
            image = await OnlineThumbCache.shared.image(for: url)
        }
    }
}

private actor OnlineThumbCache {
    static let shared = OnlineThumbCache()
    private var memory: [URL: UIImage] = [:]

    func image(for url: URL) async -> UIImage? {
        if let cached = memory[url] { return cached }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else { return nil }
            memory[url] = image
            return image
        } catch {
            return nil
        }
    }
}

// MARK: - List item wrapper

enum ImageBackgroundListItem: Identifiable {
    case bundled(ImageBackgroundDefinition)
    case custom(StoredBackgroundRecord)

    var id: String {
        switch self {
        case .bundled(let def): return def.id
        case .custom(let record): return "custom.\(record.id)"
        }
    }

    var title: String {
        switch self {
        case .bundled(let def): return def.title
        case .custom(let record): return record.title
        }
    }

    var selectionBackgroundID: String {
        switch self {
        case .bundled(let def): return def.id
        case .custom(let record): return "custom.\(record.id)"
        }
    }

    var customRef: String? {
        switch self {
        case .bundled: return nil
        case .custom(let record): return record.id
        }
    }

    var definition: ImageBackgroundDefinition {
        switch self {
        case .bundled(let def): return def
        case .custom(let record): return ImageBackgroundStore.shared.definition(for: record)
        }
    }

    var thumbnail: UIImage {
        switch self {
        case .bundled(let def):
            return ImageBackgroundAssetLoader.thumbnail(for: def)
        case .custom(let record):
            return ImageBackgroundAssetLoader.thumbnail(forRecord: record)
        }
    }

    var attributionLine: String? {
        switch self {
        case .bundled:
            return nil
        case .custom(let record):
            return record.provenance?.attributionLine
        }
    }

    var isOnlineBackground: Bool {
        switch self {
        case .bundled:
            return false
        case .custom(let record):
            return record.source == .online
        }
    }
}
