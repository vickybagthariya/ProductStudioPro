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
    @Environment(\.colorScheme) private var colorScheme

    @State private var showAbout = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var showPasteOrURLSheet = false
    @State private var pasteURLText = ""
    @State private var showImportError = false
    @State private var importErrorMessage = ""
    @State private var showSessionManager = false
    @State private var previewIndex: Int?

    var body: some View {
        NavigationStack(path: $session.navigationPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: PSDesignSpacing.lg) {
                    HomeScreenHeader(
                        sessionName: session.activeCatalogSessionName,
                        queuedCount: session.products.count,
                        showsBranding: session.showBranding,
                        businessLine: session.showBranding
                            ? "\(session.businessName) — \(session.developerLine)"
                            : nil,
                        brandMarkActive: session.brandMarkIsActive,
                        onManageSessions: { showSessionManager = true },
                        onOpenQueue: { navigate(to: .queue) },
                        onOpenSettings: { navigate(to: .settings) },
                        onOpenBrandKit: { navigate(to: .brandMark) },
                        onShowAbout: { showAbout = true }
                    )

                    HomeCreationCard(
                        selectedPhotoItems: $selectedPhotoItems,
                        isImporting: session.activeImport != nil,
                        onCapture: { navigate(to: .singleCapture) },
                        onImportFiles: {
                            guard session.activeImport == nil else { return }
                            PSDesignHaptics.tap()
                            showFileImporter = true
                        },
                        onImportURL: {
                            HomeImportSupport.handlePasteOrURLImportButton(
                                session: session,
                                pasteURLText: $pasteURLText,
                                showPasteOrURLSheet: $showPasteOrURLSheet,
                                onError: presentImportError,
                                onNavigateToQueue: navigateToQueueAfterImport
                            )
                        },
                        onImportClipboard: {
                            HomeImportSupport.importFromClipboard(
                                session: session,
                                onError: presentImportError,
                                onNavigateToQueue: navigateToQueueAfterImport
                            )
                        }
                    )

                    HomeWorkflowPresetSection(session: session)

                    HomeWorkflowShortcuts(
                        onBatchCapture: { navigate(to: .batchCapture) },
                        onMultiAngleCapture: {
                            session.prepareMultiAngleCaptureFromHome()
                            navigate(to: .singleCapture)
                        }
                    )

                    HomeContinueWorkingSection(
                        items: recentItems,
                        onSeeAll: { navigate(to: .queue) },
                        onSelectItem: { previewIndex = $0 },
                        onCapture: { navigate(to: .singleCapture) },
                        onImport: { showPhotoPicker = true }
                    )
                }
                .padding(.horizontal, PSDesignSpacing.screenHorizontal)
                .padding(.top, PSDesignSpacing.screenVertical)
                .padding(.bottom, PSDesignSpacing.xl)
            }
            .background(homeBackground)
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
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.image],
                allowsMultipleSelection: true
            ) { result in
                HomeImportSupport.importFiles(
                    result,
                    session: session,
                    onError: presentImportError,
                    onNavigateToQueue: navigateToQueueAfterImport
                )
            }
            .photosPicker(
                isPresented: $showPhotoPicker,
                selection: $selectedPhotoItems,
                maxSelectionCount: 100,
                matching: .images
            )
            .onChange(of: selectedPhotoItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                HomeImportSupport.importSelectedPhotos(
                    newItems,
                    session: session,
                    onError: presentImportError,
                    onNavigateToQueue: navigateToQueueAfterImport
                ) {
                    selectedPhotoItems = []
                }
            }
            .sheet(isPresented: $showPasteOrURLSheet) {
                PasteOrURLImportSheet(
                    urlText: $pasteURLText,
                    onImport: {
                        if HomeImportSupport.importFromPasteSheetURL(
                            pasteURLText,
                            session: session,
                            onError: presentImportError,
                            onNavigateToQueue: navigateToQueueAfterImport
                        ) {
                            showPasteOrURLSheet = false
                        }
                    },
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
            .sheet(isPresented: Binding(
                get: { previewIndex != nil },
                set: { if !$0 { previewIndex = nil } }
            )) {
                ImagePreviewPagerView(initialIndex: previewIndex ?? 0)
                    .environment(\.loadingState, loadingState)
            }
        }
    }

    // MARK: - Derived data

    private var recentItems: [HomeRecentItem] {
        Array(session.products.prefix(3).enumerated()).map { index, product in
            let metadata = session.metadataManager.productMetadata(forCapturedProductID: product.id)
            let name = metadata?.productName.nilIfEmpty
                ?? FileNameRules.baseName(for: product, namingMode: session.imageNamingMode)
            let edited = RelativeDateTimeFormatter.homeEdited.localizedString(for: product.capturedAt, relativeTo: Date())
            let subtitle = "Edited \(edited)"

            return HomeRecentItem(
                id: product.id,
                productName: name,
                subtitle: subtitle,
                statusLabel: statusLabel(for: product),
                statusTone: statusTone(for: product),
                thumbnail: QueueRowThumbnailCache.thumbnail(
                    for: product.id,
                    image: product.image,
                    displayPoints: 56
                ),
                queueIndex: index
            )
        }
    }

    private var homeBackground: some View {
        ZStack {
            PSDesignColors.background
            if colorScheme == .dark {
                RadialGradient(
                    colors: [PSDesignColors.secondaryAccent.opacity(0.08), .clear],
                    center: .topTrailing,
                    startRadius: 8,
                    endRadius: 360
                )
            } else {
                LinearGradient(
                    colors: [
                        PSDesignColors.background,
                        PSDesignColors.elevatedBackground.opacity(0.5),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
    }

    private func statusLabel(for product: CapturedProduct) -> String {
        if product.angle != .none {
            return product.angle.rawValue
        }
        if product.backgroundRemoved {
            return "Background removed"
        }
        return "In queue"
    }

    private func statusTone(for product: CapturedProduct) -> StatusChip.Tone {
        if product.backgroundRemoved { return .success }
        if product.angle != .none { return .accent }
        return .neutral
    }

    // MARK: - Navigation

    private func navigate(to route: AppRoute) {
        TapFeedback.deferAction {
            session.navigationPath.append(route)
        }
    }

    private func navigateToQueueAfterImport() {
        session.navigationPath = NavigationPath()
        session.navigationPath.append(AppRoute.queue)
    }

    private func presentImportError(_ message: String) {
        importErrorMessage = message
        showImportError = true
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension RelativeDateTimeFormatter {
    static let homeEdited: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}

// MARK: - Previews

#if DEBUG
#Preview("Home — Recent Products") {
    HomeView()
        .environmentObject(HomePreviewSupport.makeSession(productCount: 3))
        .environmentObject(LoadingStateManager())
        .environment(\.loadingState, LoadingStateManager())
}

#Preview("Home — Empty") {
    HomeView()
        .environmentObject(HomePreviewSupport.makeSession(productCount: 0))
        .environmentObject(LoadingStateManager())
        .environment(\.loadingState, LoadingStateManager())
}

#Preview("Home — Dark Mode") {
    HomeView()
        .environmentObject(HomePreviewSupport.makeSession(productCount: 2))
        .environmentObject(LoadingStateManager())
        .environment(\.loadingState, LoadingStateManager())
        .preferredColorScheme(.dark)
}
#endif

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
    static let importPhotos = "Import camera-roll shots into the active session. Uses your current Settings → Photo Quality defaults (Standard Clean). Change Settings before importing, or Reprocess in Queue later."
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
            title: "Photo Quality",
            icon: "sparkles",
            content: """
Standard Clean:
• Fast, on-device polish tuned for speed and low memory use
• Apple background removal
• Edge cleanup
• White (or custom) background
• Auto white balance, exposure, and brightness + contrast polish
• Safe, controlled sharpening
• Best for large sessions and smooth performance

Standard Clean improves lighting, edges, shadow, color, and polish. It should not intentionally alter product labels, warnings, barcodes, flavor names, or identity.
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
Bright, sharp, centered capture + Standard Clean polish = closest local professional catalog quality.
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
• Background style, gradient colors, premium presets, canvas size, fill %, rotation, flips.

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
            title: "Standard Clean (On-Device)",
            icon: "cpu",
            content: """
Standard Clean applies layered local processing: exposure, white balance, shadow/highlight recovery, vibrance, noise reduction, controlled sharpening, and edge/halo cleanup — plus your chosen background canvas.

Tuned for a fast+good performance profile: lower peak memory and quicker processing so large sessions stay smooth.

Already taken photos:
Review Before/After in Preview, tune background and fill, then Apply. Unsaved changes prompt you before you leave.
"""
        ),
        HelpSection(
            title: "Settings Explained",
            icon: "gearshape",
            content: """
Business Branding:
Customize dashboard display name.

Photo Quality:
Standard Clean polish (Auto Background Removal + Product Polish).

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
• Photo Quality: Standard Clean (fast, memory-light)
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
