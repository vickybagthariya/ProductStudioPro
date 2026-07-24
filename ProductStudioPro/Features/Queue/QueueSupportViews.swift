import SwiftUI
import UIKit

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


/// Indeterminate "Studio Magic" overlay shown while the preview reprocesses.
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
        return isApplying ? "Applying Studio Magic…" : "Building Preview…"
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
    var showsSubjectLiftHint: Bool = false
    var resetToken: String = ""

    private var footerHint: String {
        if showsSubjectLiftHint {
            return "Pinch to zoom · Double-tap for 2× · Long-press the product to lift, copy, or share"
        }
        return "Pinch to zoom · Double-tap for 2×"
    }

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

/// Lightweight toast that tells the user what Smart Upscale actually did
/// (resolution change + sharpness delta). Auto-dismisses after a few seconds.
///
/// Renders with a solid adaptive card surface — ultra-thin material proved
/// unreadable when the banner sits over photos with bright product subjects
/// because it picked up too much background colour.
struct SmartUpscaleResultBanner: View {
    let result: SmartUpscaleResult
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: result.alreadyUpscaled ? "checkmark.seal.fill" : "sparkles.rectangle.stack.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppTheme.accentText)
                .frame(width: 36, height: 36)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.border, lineWidth: 1))

            VStack(alignment: .leading, spacing: 3) {
                Text(result.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryText)
                Text(result.subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.card)
        )
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.border, lineWidth: 1.2))
        .shadow(color: Color.black.opacity(0.22), radius: 18, x: 0, y: 8)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
                if result.id == self.result.id {
                    onDismiss()
                }
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
                    Text("Queues / Sessions")
                } footer: {
                    Text("Each session is a separate photo queue (soft limit \(CaptureSessionStore.CatalogSessionLimits.softQueueCap) each). Capture and import always go into the active session.")
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
                }
            }
            .navigationTitle("Sessions")
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
