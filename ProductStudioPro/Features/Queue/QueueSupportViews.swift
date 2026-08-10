import SwiftUI
import UIKit
import PhotosUI

struct HistogramDockRow: View {
    let snapshot: ExposureHistogramSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Exposure")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(PreviewDockChrome.secondaryLabel)
                if snapshot.hasShadowClipping {
                    Label("Shadow clip", systemImage: "arrow.down.to.line.compact")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.orange)
                }
                if snapshot.hasHighlightClipping {
                    Label("Highlight clip", systemImage: "arrow.up.to.line.compact")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.orange)
                }
                Spacer(minLength: 0)
            }
            GeometryReader { geo in
                let maxV = max(1, snapshot.bins.max() ?? 1)
                let n = snapshot.bins.count
                let barW = n > 0 ? max(1, (geo.size.width - CGFloat(n - 1)) / CGFloat(n)) : 1
                HStack(alignment: .bottom, spacing: 1) {
                    ForEach(0..<n, id: \.self) { i in
                        let v = snapshot.bins[i]
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(PreviewDockChrome.primaryLabel.opacity(0.35 + 0.45 * Double(v) / Double(maxV)))
                            .frame(width: barW, height: 22 * CGFloat(v) / CGFloat(maxV))
                    }
                }
            }
            .frame(height: 24)
        }
        .padding(.horizontal, 4)
    }
}


/// Indeterminate polish overlay shown while the preview reprocesses.
///
/// Forces a dark colour scheme on its content because the overlay sits on top of
/// the preview photo (which is rendered on `Color.black`). Without this pin the
/// material adapts to the device theme and goes near-white in light mode, making
/// the white wand icon and text disappear against the underlying white product
/// canvas.
struct MagicApplyingOverlay: View {
    let isApplying: Bool
    var message: String?
    var subtitle: String?
    var progress: Double?
    var spin: Bool = true
    /// Lighter overlay for bulk queue work — less Core Animation churn.
    var compact: Bool = false

    private var displayMessage: String {
        if let message, !message.isEmpty { return message }
        return isApplying ? "Applying polish…" : "Building Preview…"
    }

    var body: some View {
        VStack(spacing: compact ? 12 : 14) {
            if compact {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(AppTheme.mint)
                    .scaleEffect(1.35)
            } else {
                ZStack {
                    Circle()
                        .stroke(AppTheme.mint.opacity(0.45), lineWidth: 7)
                        .frame(width: 82, height: 82)
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(AppTheme.mint)
                        .rotationEffect(.degrees(spin ? 360 : 0))
                        .animation(.linear(duration: 1.0).repeatForever(autoreverses: false), value: spin)
                    ForEach(0..<8, id: \.self) { i in
                        Image(systemName: "sparkle")
                            .font(.system(size: 10 + CGFloat(i % 3) * 2, weight: .bold))
                            .foregroundStyle(AppTheme.softGold)
                            .offset(x: cos(CGFloat(i) * .pi / 4) * 48, y: sin(CGFloat(i) * .pi / 4) * 48)
                            .scaleEffect(spin ? 1.18 : 0.72)
                            .animation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true).delay(Double(i) * 0.05), value: spin)
                    }
                }
            }
            Text(displayMessage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.brandPanelTitle)
                .multilineTextAlignment(.center)
            if let progress {
                ProgressView(value: min(1, max(0, progress)))
                    .progressViewStyle(.linear)
                    .tint(AppTheme.mint)
                    .frame(maxWidth: 220)
            }
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.brandPanelBody)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card + 6, style: .continuous)
                .fill(AppTheme.brandPanelFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card + 6, style: .continuous)
                .stroke(AppTheme.mint.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 18, x: 0, y: 10)
    }
}

/// Full-screen host for processing UI. Prefer mounting only via `InteractionHUDOverlay`
/// (above sheets). Do not also embed this in preview stacks.
struct MagicPreviewOverlayHost: View {
    let isApplying: Bool
    let message: String?
    var subtitle: String?
    var progress: Double?
    var compact: Bool = false
    @State private var spin = false

    var body: some View {
        ZStack {
            AppTheme.brandScrim
                .ignoresSafeArea()
                .contentShape(Rectangle())
            MagicApplyingOverlay(
                isApplying: isApplying,
                message: message,
                subtitle: subtitle,
                progress: progress,
                spin: spin,
                compact: compact
            )
            .transition(.opacity.combined(with: .scale))
        }
        .onAppear { spin = !compact }
    }
}

/// Legacy alias — prefer `InteractionHUDOverlay` (app HUD window). Kept for call-site clarity.
struct AppProcessingOverlay: View {
    var body: some View {
        InteractionHUDOverlay()
    }
}

/// Edge-to-edge full-screen photo viewer with native pinch-zoom and double-tap zoom.
struct FullScreenZoomView: View {
    @Environment(\.dismiss) private var dismiss
    let image: UIImage
    var resetToken: String = ""

    private let footerHint = "Pinch to zoom · Double-tap for 2×"

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PhotoZoomScrollView(image: image, backgroundColor: .black, resetToken: resetToken)
                .ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.22), lineWidth: 1))
                    }
                    .padding(.top, 12)
                    .padding(.trailing, 14)
                }
                Spacer()
                Text(footerHint)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
            }
        }
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    var onComplete: UIActivityViewController.CompletionWithItemsHandler?

    init(activityItems: [Any], onComplete: UIActivityViewController.CompletionWithItemsHandler? = nil) {
        self.activityItems = activityItems
        self.onComplete = onComplete
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(
            activityItems: ExportManager.activityItems(from: activityItems),
            applicationActivities: nil
        )
        vc.completionWithItemsHandler = { activityType, completed, returnedItems, error in
            onComplete?(activityType, completed, returnedItems, error)
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Queue display naming

/// Display-only helper so session titles never read as "… Queue Queue".
enum QueueDisplayNaming {
    static func queueTitle(forSessionName name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Queue" }
        if trimmed.range(of: #"\bqueue\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return trimmed
        }
        return "\(trimmed) Queue"
    }
}

// MARK: - Queue dashboard filters

enum QueueDashboardFilter: String, CaseIterable, Identifiable {
    case all
    case ready
    case attention
    case edited

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .ready: return "Ready"
        case .attention: return "Attention"
        case .edited: return "Edited"
        }
    }

    func filtered(_ products: [CapturedProduct]) -> [CapturedProduct] {
        switch self {
        case .all:
            return products
        case .ready:
            return products.filter { !$0.needsQueueAttention }
        case .attention:
            return products.filter(\.needsQueueAttention)
        case .edited:
            return products.filter(\.hasQueueManualEdits)
        }
    }
}

/// Queue quality attention issues — detection not implemented yet.
enum QueueQualityIssue: String, CaseIterable, Identifiable {
    case incompleteBackgroundRemoval
    case additionalSubjectRemaining
    case blur
    case poorLighting
    case poorImageQuality
    case croppedProduct
    case edgeArtifacts

    var id: String { rawValue }

    var symbolName: String { "exclamationmark.triangle.fill" }

    var accessibilityLabel: String {
        switch self {
        case .incompleteBackgroundRemoval: return "Background not fully removed"
        case .additionalSubjectRemaining: return "Additional subject may remain"
        case .blur: return "Blur detected"
        case .poorLighting: return "Poor lighting"
        case .poorImageQuality: return "Poor image quality"
        case .croppedProduct: return "Product may be cropped"
        case .edgeArtifacts: return "Edge artifacts"
        }
    }
}

extension CapturedProduct {
    /// Reserved for queue quality attention — returns empty until detection ships.
    var queueQualityIssues: [QueueQualityIssue] {
        []
    }

    var needsQueueAttention: Bool {
        !queueQualityIssues.isEmpty
    }

    /// User-applied preview edits (not baseline capture processing).
    var hasQueueManualEdits: Bool {
        if isGroupedCoverItem { return true }
        if rotationDegrees != 0 || flipHorizontal || flipVertical { return true }
        if photoFilter != .none && photoFilter != .standard { return true }
        if adjustAutoEnhance { return true }
        if toneAdjustments != .neutral { return true }
        if cutoutBrushMaskData != nil { return true }
        if abs(cutoutFeather - 0.35) > 0.001 { return true }
        if studioShadow != .studioDefault { return true }
        return false
    }
}

// MARK: - Filter chip row

struct QueueDashboardFilterRow: View {
    @Binding var selectedFilter: QueueDashboardFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: PSDesignSpacing.sm) {
                ForEach(QueueDashboardFilter.allCases) { filter in
                    FilterChip(
                        title: filter.title,
                        isSelected: selectedFilter == filter
                    ) {
                        selectedFilter = filter
                    }
                }

                // Visually secondary — not a fifth filter chip.
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PSDesignColors.textTertiary)
                    .frame(width: 28, height: 28)
                    .background(PSDesignColors.elevatedBackground.opacity(0.55), in: Circle())
                    .overlay(Circle().stroke(PSDesignColors.divider.opacity(0.7), lineWidth: 1))
                    .padding(.leading, PSDesignSpacing.xs)
                    .accessibilityLabel("Custom filters")
                    .accessibilityHint("Coming soon")
                    .accessibilityAddTraits(.isButton)
                    .opacity(0.7)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Add to session sheet

/// Capture / import entry points for the current session (does not create a new session).
struct QueueAddToSessionSheet: View {
    let sessionDisplayName: String
    let isImporting: Bool
    @Binding var selectedPhotoItems: [PhotosPickerItem]
    var onImportFiles: () -> Void
    var onImportURL: () -> Void
    var onImportClipboard: () -> Void
    var onSingleCapture: () -> Void
    var onBatchCapture: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 100, matching: .images) {
                        Label(isImporting ? "Importing Photos…" : "Photos", systemImage: "photo.on.rectangle")
                    }
                    .disabled(isImporting)

                    Button {
                        onDismiss()
                        onImportFiles()
                    } label: {
                        Label("Files", systemImage: "folder")
                    }
                    .disabled(isImporting)

                    Button {
                        onDismiss()
                        onImportURL()
                    } label: {
                        Label("URL", systemImage: "link")
                    }
                    .disabled(isImporting)

                    Button {
                        onDismiss()
                        onImportClipboard()
                    } label: {
                        Label("Clipboard", systemImage: "doc.on.clipboard")
                    }
                    .disabled(isImporting)
                } header: {
                    Text("Import")
                }

                Section {
                    Button {
                        onDismiss()
                        onSingleCapture()
                    } label: {
                        Label("Single Capture", systemImage: "camera")
                    }

                    Button {
                        onDismiss()
                        onBatchCapture()
                    } label: {
                        Label("Batch Capture", systemImage: "square.stack")
                    }
                } header: {
                    Text("Capture")
                } footer: {
                    Text("Adds items to \(sessionDisplayName). Does not create a new session.")
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.defaultMinListRowHeight, 44)
            .navigationTitle("Add to \(sessionDisplayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                        .foregroundStyle(DS.ColorToken.accent)
                }
                .dsHideToolbarSharedBackground()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Bulk selection bar

/// Selection summary + Create Grouped Cover + Folder / All / bulk menu (UI only).
struct QueueBulkSelectionBar: View {
    let selectedCount: Int
    let showGroupedCover: Bool
    let selectAllTitle: String
    let folderEnabled: Bool
    let bulkMenuItems: [DSDropdownActionItem]
    let bulkMenuEnabled: Bool
    var onGroupedCover: () -> Void
    var onFolder: () -> Void
    var onSelectAllToggle: () -> Void
    var onBulkMenuAction: (DSDropdownActionItem) -> Void

    var body: some View {
        VStack(spacing: PSDesignSpacing.sm) {
            if showGroupedCover {
                Button(action: onGroupedCover) {
                    Label("Create Grouped Cover", systemImage: "square.grid.2x2")
                        .font(.system(size: 16, weight: .semibold))
                        .labelStyle(.titleAndIcon)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityLabel("Create Grouped Cover")
            }

            HStack(spacing: PSDesignSpacing.sm) {
                HStack(spacing: PSDesignSpacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(PSDesignColors.primaryAccent)
                        .symbolRenderingMode(.hierarchical)
                    Text("\(selectedCount) Selected")
                        .font(PSDesignTypography.headline.weight(.bold))
                        .foregroundStyle(PSDesignColors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(selectedCount) selected")

                Spacer(minLength: 4)

                Button("Folder", action: onFolder)
                    .font(PSDesignTypography.caption.weight(.semibold))
                    .foregroundStyle(folderEnabled ? PSDesignColors.primaryAccent : PSDesignColors.textTertiary)
                    .disabled(!folderEnabled)

                Button(selectAllTitle, action: onSelectAllToggle)
                    .font(PSDesignTypography.caption.weight(.semibold))
                    .foregroundStyle(PSDesignColors.primaryAccent)

                DSDropdownActionMenu(
                    label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(bulkMenuEnabled ? PSDesignColors.primaryAccent : PSDesignColors.textTertiary)
                            .accessibilityLabel("Actions for selected photos")
                    },
                    items: bulkMenuItems,
                    isEnabled: bulkMenuEnabled
                ) { item in
                    onBulkMenuAction(item)
                }
            }
            .padding(.horizontal, PSDesignSpacing.md - 2)
            .padding(.vertical, PSDesignSpacing.sm + 2)
            .background(
                PSDesignColors.elevatedBackground,
                in: RoundedRectangle(cornerRadius: PSDesignRadius.sm, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PSDesignRadius.sm, style: .continuous)
                    .stroke(PSDesignColors.divider, lineWidth: 1)
            )
        }
    }
}

// MARK: - Collapsible search

struct QueueCollapsibleSearchBar: View {
    @Binding var text: String
    @Binding var isPresented: Bool
    var focusBinding: FocusState<Bool>.Binding

    var body: some View {
        if isPresented {
            HStack(spacing: PSDesignSpacing.sm) {
                HStack(spacing: PSDesignSpacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PSDesignColors.textSecondary)
                    TextField("Search by filename or UPC", text: $text)
                        .font(PSDesignTypography.bodyFont)
                        .foregroundStyle(PSDesignColors.textPrimary)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused(focusBinding)
                }
                .padding(.horizontal, PSDesignSpacing.md - 2)
                .padding(.vertical, PSDesignSpacing.sm + 2)
                .background(PSDesignColors.elevatedBackground, in: RoundedRectangle(cornerRadius: PSDesignRadius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: PSDesignRadius.sm, style: .continuous)
                        .stroke(PSDesignColors.divider, lineWidth: 1)
                )

                Button("Cancel") {
                    PSDesignHaptics.tap()
                    text = ""
                    focusBinding.wrappedValue = false
                    withAnimation(PSDesignMotion.springSoft) {
                        isPresented = false
                    }
                }
                .font(PSDesignTypography.caption.weight(.semibold))
                .foregroundStyle(PSDesignColors.primaryAccent)
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

// MARK: - Named sessions manager

struct CatalogSessionManagerSheet: View {
    @EnvironmentObject private var session: CaptureSessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var renameTarget: NamedCatalogSession?
    @State private var renameText = ""
    @State private var deleteTarget: NamedCatalogSession?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(session.catalogSessions) { item in
                        Button {
                            session.switchCatalogSession(to: item.id)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name)
                                        .font(DS.TypeScale.rowTitle)
                                        .foregroundStyle(DS.ColorToken.label)
                                    Text("\(session.catalogSessionProductCount(id: item.id)) photos")
                                        .font(DS.TypeScale.caption)
                                        .foregroundStyle(DS.ColorToken.secondaryLabel)
                                }
                                Spacer()
                                if item.id == session.activeCatalogSessionID {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(DS.ColorToken.accent)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Rename") {
                                renameTarget = item
                                renameText = item.name
                            }
                            .tint(.blue)
                            if session.catalogSessions.count > 1 {
                                Button("Delete", role: .destructive) {
                                    deleteTarget = item
                                }
                            }
                        }
                    }
                } header: {
                    Text("Switch session")
                } footer: {
                    Text("Tap a session to switch. Each session is a separate photo queue (soft limit \(CaptureSessionStore.CatalogSessionLimits.softQueueCap) each). Capture and import always go into the active session.")
                }

                Section {
                    HStack {
                        TextField("New session name", text: $newName)
                        Button("Add") {
                            let id = session.createCatalogSession(named: newName.isEmpty ? nil : newName)
                            newName = ""
                            _ = id
                            dismiss()
                        }
                        .disabled(session.activeImport != nil)
                    }
                } header: {
                    Text("Create session")
                }
            }
            .navigationTitle("Manage Sessions")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(DS.ColorToken.accent)
                }
                .dsHideToolbarSharedBackground()
            }
            .alert("Rename session", isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )) {
                TextField("Name", text: $renameText)
                Button("Cancel", role: .cancel) { renameTarget = nil }
                Button("Save") {
                    if let target = renameTarget {
                        session.renameCatalogSession(id: target.id, to: renameText)
                    }
                    renameTarget = nil
                }
            }
            .alert("Delete session?", isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            )) {
                Button("Cancel", role: .cancel) { deleteTarget = nil }
                Button("Delete", role: .destructive) {
                    if let target = deleteTarget {
                        _ = session.deleteCatalogSession(id: target.id)
                    }
                    deleteTarget = nil
                }
            } message: {
                Text("Deletes this queue and its photos from Product Studio Pro. Files you already shared elsewhere are not affected.")
            }
        }
    }
}
