import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers

enum AppRoute: Hashable {
    case singleCapture
    case batchCapture
    case queue
    case settings
    case brandMark
}

struct HomeView: View {
    @EnvironmentObject private var session: CaptureSessionStore
    @Environment(\.loadingState) private var loadingState
    @State private var showAbout = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showFileImporter = false
    @State private var showPasteOrURLSheet = false
    @State private var pasteURLText = ""
    @State private var showImportError = false
    @State private var importErrorMessage = ""
    @State private var showSessionManager = false
    @State private var templateChannelFilter: CatalogTemplateChannel?
    @State private var templateAppliedToast: String?
    @State private var previewIndex: Int?

    var body: some View {
        NavigationStack(path: $session.navigationPath) {
            AppScreenScaffold(
                title: "Product Studio",
                subtitle: "Capture. Polish. Ship catalog photos.",
                showsHome: false,
                layout: .scroll,
                usesLargeTitle: true,
                headerAccessory: { homeHeaderAccessory }
            ) {
                if session.showBranding {
                    Text("\(session.businessName) — \(session.developerLine)")
                        .font(DS.TypeScale.caption)
                        .foregroundStyle(DS.ColorToken.secondaryLabel)
                }

                studioHeroSection
                recentWorkSection
                templatePacksSection
                compactImportSection
                studioSecondaryActions
                howItWorksFooter
            }
            .navigationBarHidden(true)
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .singleCapture: CaptureFlowView(mode: .single)
                case .batchCapture: CaptureFlowView(mode: .batch)
                case .queue: QueueView()
                case .settings: SettingsView()
                case .brandMark: BrandMarkEditorView()
                }
            }
            .sheet(isPresented: $showAbout) { AboutHowItWorksView() }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
                importFiles(result)
            }
            .onChange(of: selectedPhotoItems) { _, newItems in
                importSelectedPhotos(newItems)
            }
            .sheet(isPresented: $showPasteOrURLSheet) {
                PasteOrURLImportSheet(
                    urlText: $pasteURLText,
                    onImport: { importFromPasteSheetURL() },
                    onCancel: { showPasteOrURLSheet = false }
                )
            }
            .alert("Couldn’t Import", isPresented: $showImportError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importErrorMessage)
            }
            .sheet(isPresented: $showSessionManager) {
                CatalogSessionManagerSheet()
                    .environmentObject(session)
            }
            .overlay(alignment: .bottom) {
                if let templateAppliedToast {
                    DSCaptureToast(text: templateAppliedToast)
                        .padding(.bottom, 28)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .sheet(isPresented: Binding(
                get: { previewIndex != nil },
                set: { if !$0 { previewIndex = nil } }
            )) {
                ImagePreviewPagerView(initialIndex: previewIndex ?? 0)
                    .environment(\.loadingState, loadingState)
            }
        }
    }

    private var homeHeaderAccessory: some View {
        Button { showAbout = true } label: {
            Image(systemName: "info.circle")
                .font(DS.TypeScale.sectionTitle)
                .foregroundStyle(DS.ColorToken.accent)
                .padding(10)
                .background(DS.ColorToken.backgroundTertiary, in: Circle())
                .overlay(Circle().stroke(DS.ColorToken.separator, lineWidth: 1))
        }
        .buttonStyle(.plainPressable)
        .accessibilityLabel("How It Works")
    }

    // MARK: - Studio home sections

    private var studioHeroSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.stack) {
            HStack(spacing: DS.Space.stack) {
                Button {
                    TapFeedback.deferAction { showSessionManager = true }
                } label: {
                    Label(session.activeCatalogSessionName, systemImage: "folder")
                        .font(DS.TypeScale.caption.weight(.semibold))
                        .foregroundStyle(DS.ColorToken.label)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(DS.ColorToken.backgroundTertiary, in: Capsule())
                        .overlay(Capsule().stroke(DS.ColorToken.separator, lineWidth: 1))
                }
                .buttonStyle(.plainPressable)
                .accessibilityLabel("Manage sessions")

                Button {
                    TapFeedback.deferAction { session.navigationPath.append(AppRoute.queue) }
                } label: {
                    Text("\(session.products.count) in queue")
                        .font(DS.TypeScale.caption.weight(.semibold))
                        .foregroundStyle(DS.ColorToken.secondaryLabel)
                }
                .buttonStyle(.plainPressable)

                Spacer(minLength: 0)
            }

            Button {
                TapFeedback.deferAction { session.navigationPath.append(AppRoute.singleCapture) }
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Label("New shoot", systemImage: "camera.fill")
                        .font(.system(size: 22, weight: .bold))
                    Text("Single product · #\(session.nextSequence)")
                        .font(DS.TypeScale.caption)
                        .opacity(0.9)
                }
                .foregroundStyle(DS.ColorToken.onAccent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22)
                .padding(.vertical, 22)
                .background(DS.ColorToken.primaryButtonFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            }
            .buttonStyle(.plainPressable)
            .accessibilityLabel("New shoot")
            .accessibilityHint("Start single product capture")

            HStack(spacing: DS.Space.stack) {
                Button {
                    TapFeedback.deferAction { session.navigationPath.append(AppRoute.batchCapture) }
                } label: {
                    Label("Batch mode", systemImage: "square.stack.3d.up.fill")
                        .font(DS.TypeScale.bodyEmphasis)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())

                Button {
                    TapFeedback.deferAction { session.navigationPath.append(AppRoute.queue) }
                } label: {
                    Label("Queue", systemImage: "list.bullet.rectangle")
                        .font(DS.TypeScale.bodyEmphasis)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            if session.multiAngleEnabled {
                Text(session.multiAngleStatusLine)
                    .font(DS.TypeScale.micro)
                    .foregroundStyle(DS.ColorToken.secondaryLabel)
            }
        }
    }

    private var recentWorkSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.tight) {
            HStack {
                Text("Recent in session")
                    .font(DS.TypeScale.sectionTitle)
                    .foregroundStyle(DS.ColorToken.label)
                Spacer()
                if !session.products.isEmpty {
                    Button("See all") {
                        TapFeedback.deferAction { session.navigationPath.append(AppRoute.queue) }
                    }
                    .font(DS.TypeScale.caption.weight(.semibold))
                    .foregroundStyle(DS.ColorToken.accent)
                }
            }

            if session.products.isEmpty {
                Text("Your next shoot will show up here.")
                    .font(DS.TypeScale.caption)
                    .foregroundStyle(DS.ColorToken.secondaryLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 18)
                    .padding(.horizontal, 14)
                    .background(DS.ColorToken.backgroundTertiary, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Space.tight) {
                        ForEach(Array(session.products.prefix(10).enumerated()), id: \.element.id) { index, product in
                            Button {
                                TapFeedback.deferAction { previewIndex = index }
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Image(uiImage: QueueRowThumbnailCache.thumbnail(for: product.id, image: product.image, displayPoints: 72))
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 72, height: 72)
                                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.thumbnail, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: DS.Radius.thumbnail, style: .continuous)
                                                .stroke(DS.ColorToken.separator, lineWidth: 1)
                                        )
                                    Text(product.upc)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(DS.ColorToken.secondaryLabel)
                                        .lineLimit(1)
                                        .frame(width: 72, alignment: .leading)
                                }
                            }
                            .buttonStyle(.plainPressable)
                            .accessibilityLabel("Preview \(product.upc)")
                            .accessibilityHint("Opens image preview")
                        }
                    }
                }
            }
        }
    }

    private var templatePacksSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.tight) {
            HStack {
                Text("Templates")
                    .font(DS.TypeScale.sectionTitle)
                    .foregroundStyle(DS.ColorToken.label)
                Spacer()
                Text("Sets canvas, polish & background")
                    .font(DS.TypeScale.micro)
                    .foregroundStyle(DS.ColorToken.tertiaryLabel)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    templateChannelChip(title: "All", selected: templateChannelFilter == nil) {
                        templateChannelFilter = nil
                    }
                    ForEach(CatalogTemplateChannel.allCases) { channel in
                        templateChannelChip(
                            title: channel.title,
                            selected: templateChannelFilter == channel
                        ) {
                            templateChannelFilter = channel
                        }
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(CatalogTemplateLibrary.orderedPacks(
                        for: templateChannelFilter,
                        activeID: session.activeCatalogTemplatePackID
                    )) { pack in
                        let isActive = session.activeCatalogTemplatePackID == pack.id
                        Button {
                            InteractionHaptics.selection(vibrate: session.vibrateEnabled)
                            session.applyCatalogTemplate(pack)
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                                templateAppliedToast = pack.id == CatalogTemplateLibrary.appDefaultsID
                                    ? "App Defaults restored"
                                    : "Template · \(pack.name)"
                            }
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 2_000_000_000)
                                withAnimation { templateAppliedToast = nil }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: -6) {
                                    ForEach(Array(pack.backgroundPreset.hexes.prefix(3).enumerated()), id: \.offset) { _, hex in
                                        Circle()
                                            .fill(Color(hex: hex))
                                            .frame(width: 18, height: 18)
                                            .overlay(Circle().stroke(DS.ColorToken.background, lineWidth: 1.5))
                                    }
                                    Spacer(minLength: 0)
                                    if isActive {
                                        Text("In use")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(DS.ColorToken.onAccent)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(DS.ColorToken.primaryButtonFill, in: Capsule())
                                    } else {
                                        Image(systemName: pack.id == CatalogTemplateLibrary.appDefaultsID
                                              ? "house.fill"
                                              : pack.channel.systemImage)
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(DS.ColorToken.secondaryLabel)
                                    }
                                }
                                Text(pack.name)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(DS.ColorToken.label)
                                    .lineLimit(1)
                                Text(pack.subtitle)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(DS.ColorToken.secondaryLabel)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(12)
                            .frame(width: 148, alignment: .leading)
                            .background(DS.ColorToken.backgroundSecondary, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                                    .stroke(
                                        isActive ? DS.ColorToken.accent : DS.ColorToken.separator,
                                        lineWidth: isActive ? 2 : 1
                                    )
                            )
                        }
                        .buttonStyle(.plainPressable)
                        .accessibilityLabel(isActive ? "\(pack.name), in use" : "Apply template \(pack.name)")
                        .accessibilityAddTraits(isActive ? .isSelected : [])
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.86), value: session.activeCatalogTemplatePackID)
            }
        }
    }

    private func templateChannelChip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            InteractionHaptics.selection(vibrate: session.vibrateEnabled)
            action()
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(selected ? DS.ColorToken.onAccent : DS.ColorToken.label)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    selected ? DS.ColorToken.primaryButtonFill : DS.ColorToken.backgroundTertiary,
                    in: Capsule()
                )
                .overlay(Capsule().stroke(DS.ColorToken.separator, lineWidth: selected ? 0 : 1))
        }
        .buttonStyle(.plainPressable)
    }

    private var compactImportSection: some View {
        let isImportingPhotos = session.activeImport != nil
        return VStack(alignment: .leading, spacing: DS.Space.tight) {
            Text("Import")
                .font(DS.TypeScale.sectionTitle)
                .foregroundStyle(DS.ColorToken.label)

            HStack(spacing: DS.Space.stack) {
                PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 100, matching: .images) {
                    Label(isImportingPhotos ? "Importing…" : "Photos", systemImage: "photo.on.rectangle.angled")
                        .font(DS.TypeScale.bodyEmphasis)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(isImportingPhotos)

                Button {
                    guard !isImportingPhotos else { return }
                    InteractionHaptics.tap(vibrate: session.vibrateEnabled)
                    showFileImporter = true
                } label: {
                    Label("Files", systemImage: "folder")
                        .font(DS.TypeScale.bodyEmphasis)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(isImportingPhotos)

                Button { handlePasteOrURLImportButton() } label: {
                    Label("URL", systemImage: "link")
                        .font(DS.TypeScale.bodyEmphasis)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(isImportingPhotos)
            }

            Text(importQualityStatusLine)
                .font(DS.TypeScale.micro)
                .foregroundStyle(DS.ColorToken.secondaryLabel)
        }
    }

    private var studioSecondaryActions: some View {
        HStack(spacing: DS.Space.stack) {
            Button {
                TapFeedback.deferAction { session.navigationPath.append(AppRoute.brandMark) }
            } label: {
                Label(session.brandMarkIsActive ? "Brand Kit · On" : "Brand Kit", systemImage: "seal")
                    .font(DS.TypeScale.bodyEmphasis)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())

            Button {
                TapFeedback.deferAction { session.navigationPath.append(AppRoute.settings) }
            } label: {
                Label("Settings", systemImage: "gearshape.fill")
                    .font(DS.TypeScale.bodyEmphasis)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    private var howItWorksFooter: some View {
        Button {
            InteractionHaptics.tap(vibrate: session.vibrateEnabled)
            showAbout = true
        } label: {
            Label("How It Works", systemImage: "info.circle")
                .font(DS.TypeScale.bodyEmphasis)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(SecondaryButtonStyle())
        .accessibilityHint(DashboardHelpTip.howItWorks)
        .padding(.top, DS.Space.tight)
        .padding(.bottom, DS.Space.stack)
    }

    private var importQualityStatusLine: String {
        if session.photoEnhancementMode == .studioAI {
            return "Imports use Settings · Studio AI \(session.studioAIStrength.rawValue)"
        }
        return "Imports use Settings · Standard Clean"
    }

    private func handlePasteOrURLImportButton() {
        guard session.activeImport == nil else { return }
        InteractionHaptics.tap(vibrate: session.vibrateEnabled)
        let snapshot = ClipboardURLImageImport.readClipboard()
        if !snapshot.images.isEmpty {
            importUIImageBatch(snapshot.images, progressMessage: "Importing from clipboard…")
            return
        }
        if !snapshot.urls.isEmpty {
            importImagesFromURLs(snapshot.urls)
            return
        }
        pasteURLText = snapshot.suggestedURLText
        showPasteOrURLSheet = true
    }

    private func importFromPasteSheetURL() {
        let trimmed = pasteURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = ClipboardURLImageImport.parseURL(from: trimmed) else {
            importErrorMessage = ClipboardURLImageImportError.invalidURL.localizedDescription
            showImportError = true
            return
        }
        showPasteOrURLSheet = false
        importImagesFromURLs([url])
    }

    private func importUIImageBatch(_ images: [UIImage], progressMessage: String) {
        guard !images.isEmpty else { return }
        let gate = session.gateAddingPhotos(count: images.count)
        if gate.isBlocked {
            importErrorMessage = gate.userMessage
            showImportError = true
            return
        }
        // Clipboard paste already decoded — stream through the same append path without re-holding a second copy set.
        Task {
            await MainActor.run {
                session.beginSessionPersistenceBatch()
                session.updateActiveImport(completed: 0, total: images.count, message: progressMessage)
            }
            let imported = await session.streamImportCatalogImages(
                total: images.count,
                progressMessage: progressMessage
            ) { index in
                guard index >= 0, index < images.count else { return nil }
                return images[index]
            }
            await MainActor.run {
                session.endSessionPersistenceBatch()
                if imported > 0 {
                    session.navigationPath = NavigationPath()
                    session.navigationPath.append(AppRoute.queue)
                } else {
                    importErrorMessage = ClipboardURLImageImportError.unsupportedImage.localizedDescription
                    showImportError = true
                }
                session.clearActiveImport()
            }
        }
    }

    private func importImagesFromURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let gate = session.gateAddingPhotos(count: urls.count)
        if gate.isBlocked {
            importErrorMessage = gate.userMessage
            showImportError = true
            return
        }
        Task {
            await MainActor.run {
                session.beginSessionPersistenceBatch()
                session.updateActiveImport(completed: 0, total: urls.count, message: "Downloading image…")
            }
            let imported = await session.streamImportCatalogImages(
                total: urls.count,
                progressMessage: "Downloading image…"
            ) { index in
                guard index >= 0, index < urls.count else { return nil }
                return try? await ClipboardURLImageImport.downloadImage(from: urls[index])
            }
            await MainActor.run {
                session.endSessionPersistenceBatch()
                if imported > 0 {
                    session.navigationPath = NavigationPath()
                    session.navigationPath.append(AppRoute.queue)
                } else {
                    importErrorMessage = ClipboardURLImageImportError.downloadFailed.localizedDescription
                    showImportError = true
                }
                session.clearActiveImport()
            }
        }
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, !urls.isEmpty else { return }
        let gate = session.gateAddingPhotos(count: urls.count)
        if gate.isBlocked {
            importErrorMessage = gate.userMessage
            showImportError = true
            return
        }
        Task {
            await MainActor.run { session.beginSessionPersistenceBatch() }
            let imported = await session.streamImportCatalogImages(
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
                if imported > 0 {
                    session.navigationPath = NavigationPath()
                    session.navigationPath.append(AppRoute.queue)
                }
                session.clearActiveImport()
            }
        }
    }

    private func importSelectedPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        let gate = session.gateAddingPhotos(count: items.count)
        if gate.isBlocked {
            importErrorMessage = gate.userMessage
            showImportError = true
            selectedPhotoItems = []
            return
        }
        Task {
            await MainActor.run { session.beginSessionPersistenceBatch() }
            let imported = await session.streamImportCatalogImages(
                total: items.count,
                progressMessage: "Importing from Photos…"
            ) { index in
                guard index >= 0, index < items.count else { return nil }
                guard let data = try? await items[index].loadTransferable(type: Data.self) else { return nil }
                return autoreleasepool { ImageImportDecoder.uiImage(from: data) ?? UIImage(data: data) }
            }
            await MainActor.run {
                session.endSessionPersistenceBatch()
                if imported > 0 {
                    session.navigationPath = NavigationPath()
                    session.navigationPath.append(AppRoute.queue)
                }
                selectedPhotoItems = []
                session.clearActiveImport()
            }
        }
    }
}

struct AboutHowItWorksView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            AppScreenScaffold(title: "How It Works", showsHome: false, layout: .scroll) {
                Text("Capture, polish, and organize product photos in named sessions. Apply Home templates for canvas, polish, and background defaults; stamp Brand Kit text, logo, or image names; fine-tune in Queue preview; then export as ZIP (JPG + CSV), JPG, transparent PNG cutouts, or CSV only.")
                    .font(DS.TypeScale.body)
                    .foregroundStyle(DS.ColorToken.label)

                ForEach(HomeHelpText.longSections) { section in
                    DSCard {
                        DisclosureGroup {
                            Text(section.content)
                                .font(DS.TypeScale.body)
                                .foregroundStyle(DS.ColorToken.secondaryLabel)
                                .padding(.vertical, DS.Space.stack)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } label: {
                            Label(section.title, systemImage: section.icon)
                                .font(DS.TypeScale.rowTitle)
                                .foregroundStyle(DS.ColorToken.label)
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(DS.ColorToken.accent)
                }
                .dsHideToolbarSharedBackground()
            }
        }
    }
}

struct HelpSection: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let content: String
}

/// Short contextual tips for dashboard controls (tap the info icon beside each section).
enum DashboardHelpTip {
    static let howItWorks = "Open the full guide: capture → polish → sessions → export."
    static let sessionStatus = "Sessions are named photo queues. Tap the Session tile to switch, rename, or create a folder. Queued is the count in the active session; Next is the upcoming product number."
    static let singleCapture = "One product: photo → scan or name → Queue. Multi-angle: all angles first, then one UPC for the set."
    static let batchMode = "Capture many in a row. With multi-angle on: shoot every angle first, then one UPC names UPC-1, UPC-2, …. Camera settings carry between shots."
    static let importPhotos = "Import camera-roll shots into the active session. Uses your current Settings → Photo Quality mode (Standard Clean or Studio AI). Change Settings before importing, or Reprocess in Queue later."
    static let importFiles = "Bring images from the Files app — including iCloud Drive and other cloud locations you enable under Files → Locations (Google Drive, Dropbox, OneDrive, etc.). Uses the same Settings → Photo Quality mode as Photos import."
    static let importPasteOrURL = "Paste a photo or image URL into the active session. Uses your current Settings → Photo Quality mode. URL import requires network."
    static let viewQueue = "Polish, markup, and export from the active session. Share as ZIP, JPG, PNG cutouts, or CSV."
    static let brandMark = "Optional Brand Mark (company name + logo) and Image Name (file/UPC stamp). Separate caption-plate and logo opacity, edge padding, and line wrap. Applies on capture, import, Apply, and Reprocess. Per photo: ⋯ menu → Hide Brand Kit, or Edit & Polish."
    static let templates = "One-tap packs for canvas, polish, and background. App Defaults is pinned first and restores the baseline (including Original style filter). Other templates do not change your Settings default style filter."
    static let settings = "Photo quality, default style filter, compression, naming, multi-angle, and background session defaults. Design backgrounds in Preview → Format Background or Home templates."
}

enum HomeHelpText {
    static let longSections: [HelpSection] = [
        HelpSection(
            title: "Main Workflows",
            icon: "rocket.launch",
            content: """
Single Capture:
Best for one product at a time.
1. Tap Single Product Capture.
2. Take the photo in bright, even lighting.
3. Scan UPC/barcode or enter a name.
4. The app processes the image.
5. Review in Queue preview.
6. Share when ready.

Batch Mode:
Best for large inventory sessions.
1. Tap Batch Mode — choose auto-open camera or tap each time.
2. Set zoom/lighting once; settings carry across captures.
3. Capture + scan sequentially.
4. Items auto-save into the active session’s Queue.
5. Preview, compare Before/After, adjust quality, or reprocess if needed.
6. Export when the batch is ready.

Tip:
After capture, the Live Capture Quality Assistant checks lighting, sharpness, and framing. If it warns you, retake for better final polish.
"""
        ),
        HelpSection(
            title: "Sessions (Named Queues)",
            icon: "folder",
            content: """
Sessions are separate folders — each with its own queue and soft item limit.

• Home shows the active session name beside Queued / Next.
• Tap Sessions (or the folder control in Queue) to switch, rename, add, or delete.
• Capture and imports always land in the active session.
• Export only includes photos from the active session.
• Deleting a session removes its local queue; you can’t delete the last remaining session.

Use Sessions to keep brands, days, or marketplaces organized instead of one flat list.
"""
        ),
        HelpSection(
            title: "Memory & Performance",
            icon: "gauge.with.dots.needle.67percent",
            content: """
Product Studio keeps a safety cushion of free memory so the phone stays responsive — it will not try to use all available RAM.

Soft queue limit:
• About 200 photos per session (import, capture, and folder moves respect this).

Live memory protection:
• Watches free memory and device heat.
• Under pressure: clears caches, releases unused originals, and may unload off-screen queue images (they reload from disk when you open them).
• Import/capture may run one photo at a time, or pause with tips if free memory is too low.

If you see “Keep the App Smooth” or “Can’t Add More Photos”:
• Export finished work, then clear or start a new session folder.
• Close Preview / Markup when you’re done.
• Pause bulk Enhance / Reprocess until memory recovers.
• Import fewer photos at a time.
"""
        ),
        HelpSection(
            title: "Home Templates",
            icon: "square.grid.2x2",
            content: """
Templates on Home set canvas size, fill, polish mode, and background look for new captures and imports.

• App Defaults is pinned first — restores the app baseline (Standard Clean, white background, Original style filter).
• Other packs (Marketplace, Premium, Hero, Studio, Bold, and more) apply their canvas, polish, and background presets.
• Templates do not sticky your Style filter — that lives in Settings → Default style filter (except App Defaults, which resets it to Original).
• Active template shows “In use” and stays at the front of the strip.
• Already-queued photos are unchanged until you Apply, Reprocess, or edit in Preview.
"""
        ),
        HelpSection(
            title: "Brand Kit",
            icon: "seal",
            content: """
Optional stamps on catalog images — off by default (some marketplaces prefer clean photos).

Brand Mark:
• Company name and/or logo
• Position (3×3 grid), font, size, caption plate color/opacity, logo size (% of short edge) and opacity
• Edge padding (default 2.5%) and optional line wrap
• Brand Mark and Image Name cannot share the same corner/slot

Image Name:
• Stamps the photo’s file / UPC name independently of Brand Mark
• Own size, style, caption colors, position, padding, and wrap

When it applies:
• Capture, import, Preview Apply, Queue Reprocess, and Apply Brand Kit to queue
• Share uses the already-processed image
• Per photo: ⋯ menu → Hide Brand Kit, or turn off in Edit & Polish
• Reset Brand Kit to defaults keeps your company name and logo file; Apply to queue afterward if needed
"""
        ),
        HelpSection(
            title: "Photo Quality Modes",
            icon: "sparkles",
            content: """
Standard Clean:
• Fastest mode
• Apple background removal
• Edge cleanup
• White background
• Brightness + contrast polish
• Best for speed

Studio AI Natural:
• Safer premium enhancement
• Auto white balance
• Better edge smoothing
• Better color balance
• Sharper image
• Soft professional shadow

Studio AI Strong:
• More aggressive enhancement
• Stronger local clarity
• Stronger denoise
• Better lighting correction
• Cleaner white/custom canvas
• Great for wholesale websites

Studio AI Ultra:
• Maximum safe on-device enhancement
• Softer than previous builds to prevent pixel breakup
• Stronger shadow/highlight recovery
• Strong denoise with controlled detail
• Better product edge smoothing
• Hero image feel
• Best for product showcases

Studio AI improves lighting, edges, shadow, color, and polish. It should not intentionally alter product labels, warnings, barcodes, flavor names, or identity.
"""
        ),
        HelpSection(
            title: "Catalog-Ready Results",
            icon: "camera.aperture",
            content: """
For best final output:
• Use rear camera
• Use highest camera quality
• Bright, even lighting
• Avoid harsh shadows
• Keep product upright
• Fill most of the frame
• Keep camera steady
• Use a clean background when possible

Reality check:
AI can dramatically improve good photos.
AI cannot fully rescue blurry, dark, or severely poor captures.

Best formula:
Good Capture Assistant score + Studio AI Ultra = closest local professional catalog quality.
"""
        ),
        HelpSection(
            title: "Capture Quality Assistant",
            icon: "viewfinder.circle",
            content: """
Before taking the shot, the camera shows:
• Center product box
• Edge boundary guide
• Live score
• Light, sharpness, and framing scores
• Move closer guidance
• Too much shadow / too dark warning
• Glare warning
• Hold steady warning

After every photo, the app also checks brightness, blur, framing, crop risk, and glare.

If the photo may not polish well, you’ll see Retake Recommended.
Choose Retake for best quality or Use Anyway to continue quickly.

Local Studio AI works best when the original capture is bright, sharp, and centered.
"""
        ),
        HelpSection(
            title: "Multi-Angle Mode",
            icon: "camera.viewfinder",
            content: """
Capture every enabled angle first (Front, Back, Side 1, Side 2 — choose which in Settings or on the capture screen).

Then scan one UPC (or enter one name). Files are named:
12345-1.jpg
12345-2.jpg
12345-3.jpg

Queue badges still show Front / Back / Side. Use Group by UPC in Queue to keep a set together.

Best for:
• Product detail pages
• ERP systems
• Wholesale sites
• Marketplace listings

Tip:
Disable unused angles in Settings to speed up workflow.
"""
        ),
        HelpSection(
            title: "Naming Settings",
            icon: "tag",
            content: """
UPC Scan (Recommended):
• Exact barcode filename
• ERP friendly
• Fastest for inventory
• Reduces naming mistakes

Random:
• Testing
• Temporary use

Manual:
• Missing barcode
• Custom SKU
• Product variants
"""
        ),
        HelpSection(
            title: "Queue, Export & Duplicate Protection",
            icon: "square.stack.3d.up",
            content: """
Queue:
Your holding area for the active session before export.
• Preview (including Markup — see “Markup & annotations”)
• Delete / retake / reprocess
• Bulk select and share

Export options (Queue & preview):
1. ZIP (JPG + CSV) — best for 2+ items; packaged handoff
2. JPG — best for one photo; also works for bulk; asks whether to include CSV
3. PNG transparent cutouts — keeps transparency when backgrounds were removed; optional CSV ask
4. CSV only — inventory list without images

ZIP and JPG size:
Settings → Compression / Sharing controls JPG quality so ZIP attachments stay predictable for Mail.

Duplicate protection:
If a barcode already exists:
• Replace = overwrite previous
• Add Anyway = keep duplicate

Apply Current Enhancements:
After changing Settings, reprocess selected photos from each original using your current polish, canvas, and fill settings. For one-photo control, open Preview.
"""
        ),
        HelpSection(
            title: "Creative Backgrounds & Soft Floor",
            icon: "paintpalette",
            content: """
Where to design:
• Preview → Format Background — solid, gradient, stops, direction, and premium looks
• Home → Templates — one-tap canvas + polish + background packs
• Settings → Background Defaults — session starting point only (reset to white, reset on launch)

Background options:
• White is the default for catalog-style product images
• Solid color or gradient fills (linear, radial, angular, mesh)
• Premium Halo, Soft Floor, Shelf Plinth, and other curated presets in Format Background
• Match product colors samples the subject and updates stops in place

Preview protection:
If you change background or enhancement settings and try to leave, share, or move away, the app asks you to Apply, Leave Anyway, or Cancel.

With saved Markup:
Changing background style or premium presets rebuilds from the original capture. The app offers Keep Markup (cancel) or Remove Markup & apply. Filters do not remove Markup.
"""
        ),
        HelpSection(
            title: "Markup & annotations",
            icon: "pencil.tip.crop.circle",
            content: """
When you open Markup, choose Text or Draw at the bottom — the pencil bar stays hidden until you tap Draw.

Text:
• Tap Text → add a box, double-tap to type, Done on the keyboard when finished.
• Toolbar: font, size, bold/italic/underline, separate text vs box fill colors, alignment, padding, margin, gradient presets, duplicate/delete.
• Text and box colors are independent.
• The box auto-grows as you type.
• Long-press a text box for Edit, Duplicate, or Delete.
• Drag to move; corner handles to resize.

Drawing:
• Tap Draw → Apple PencilKit tools appear. Tap Text again to return to text mode.

Save workflow:
1. Markup Save (checkmark) → live preview shows photo + drawing + text.
2. Preview Apply → writes into the queue item.

Compatibility:
• Filters and Auto enhance work on the saved Markup preview without removing it.
• Changing background style, gradient presets, or canvas/enhancement mode rebuilds from the original — the app warns you first.
• Preview Undo restores the last preview snapshot, including saved Markup when captured.
"""
        ),
        HelpSection(
            title: "What works together in Preview",
            icon: "arrow.triangle.merge",
            content: """
Safe together (no Markup loss):
• Photo filters + filter amount + Auto enhance on the current preview image.
• Markup (after Save) + filters on top of that preview.

Rebuilds from original (app asks if Markup is saved):
• Background style, gradient colors, premium presets, canvas size, fill %, rotation, flips, Studio AI quality chips.

Order that avoids surprises:
1. Adjust background/enhancement first (or accept a rebuild warning later).
2. Markup Save → then filters if needed → Preview Apply.

Undo:
• Toolbar undo/redo restores panel settings and the saved preview bitmap when snapshotted.
• It does not step through individual Markup strokes — use Markup’s … menu for that while still in Markup.
"""
        ),
        HelpSection(
            title: "Background Removal & Edge Cleanup",
            icon: "wand.and.stars",
            content: """
Background Removal ON:
• Apple subject lift
• Advanced edge cleanup
• Dehalo and border smoothing
• White or custom-color canvas
• Catalog-ready exports

Background Removal OFF:
• Keeps the original scene
• Useful for archive or manual editing

Edge Cleanup:
Reduces rough native cutout edges for cleaner product borders.
"""
        ),
        HelpSection(
            title: "Studio AI (On-Device)",
            icon: "cpu",
            content: """
Studio AI applies layered local processing: exposure, white balance, shadow/highlight recovery, vibrance, noise reduction, controlled sharpening, edge smoothing, halo cleanup, and soft studio shadow — plus your chosen background canvas.

Strength:
• Natural — safest everyday polish
• Strong — stronger web-ready correction
• Ultra — maximum on-device hero-image polish

Already taken photos:
Compare Standard / Natural / Strong / Ultra in Preview, review Before/After, tune background and fill, then Apply. Unsaved changes prompt you before you leave.

Smart Upscale:
On-device Lanczos pass with micro-sharpening (capped resolution). After it runs, a banner reports the from/to size. Disabled until you reprocess from the original so a photo isn’t upscaled repeatedly.
"""
        ),
        HelpSection(
            title: "Settings Explained",
            icon: "gearshape",
            content: """
Business Branding:
Customize dashboard display name.

Photo Quality:
Standard Clean or Studio AI (Natural / Strong / Ultra), Smart Color Accuracy, Smart Upscale on export.

Default style filter:
Applied to new captures and imports only (default Original). Home templates do not change this — App Defaults resets it to Original. Change per photo in Edit & Polish.

Background Defaults:
Starting point for the session. Design fills in Preview → Format Background or apply a Home template. Optional reset to white on launch.

Canvas & Export:
Export profiles (Amazon / Shopify / Walmart / Custom) set square canvas, fill, JPG quality, and compress. Editing those controls switches the profile back to Custom.
• 1200×1200 = Standard · 1600×1600 = Premium detail
• Fill Ratio 95% recommended
• Compress Before Sharing keeps ZIP/JPG email-friendly

Naming & Multi-Angle:
UPC scan, Random, or Manual; enable angles in Settings or on the capture screen.

Recommended setup:
• Background Removal: ON
• Product Polish: ON
• Photo Quality: Studio AI Strong or Ultra
• Smart Color Accuracy: ON
• Default style filter: Original (or pick a look you always want on new shots)
• Background: White for catalog · Home templates or Format Background for hero looks
• Naming: UPC
• Fill Ratio: 95%
• Rear Camera

New captures use your saved Settings. Manual Preview changes stay photo-specific and do not change global Settings.
"""
        ),
    ]
}
