import SwiftUI

/// Expandable Studio Preset selector with category chips and Preset Styles preview cards.
struct HomeStudioPresetSection: View {
    @ObservedObject var session: CaptureSessionStore
    @State private var isExpanded = false
    @State private var appliedToast: String?

    private var activeDefinition: StudioPresetDefinition {
        StudioPresetLibrary.definition(for: session.studioPreset)
    }

    private var activePack: CatalogTemplatePack {
        CatalogTemplateLibrary.all.first(where: { $0.id == session.activeCatalogTemplatePackID })
            ?? CatalogTemplateLibrary.appDefaults
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PSDesignSpacing.sm) {
            collapseHeader

            if isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if let appliedToast {
                Text(appliedToast)
                    .font(PSDesignTypography.footnote.weight(.medium))
                    .foregroundStyle(PSDesignColors.primaryAccent)
                    .transition(PSDesignMotion.fade)
            }
        }
        .animation(PSDesignMotion.springSoft, value: isExpanded)
        .animation(PSDesignMotion.springSoft, value: session.studioPreset)
        .animation(PSDesignMotion.springSoft, value: session.activeCatalogTemplatePackID)
    }

    private var collapseHeader: some View {
        Button {
            PSDesignHaptics.tap()
            withAnimation(PSDesignMotion.springSoft) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: PSDesignSpacing.sm) {
                VStack(alignment: .leading, spacing: PSDesignSpacing.xs) {
                    Text("Studio Preset")
                        .font(PSDesignTypography.caption.weight(.semibold))
                        .foregroundStyle(PSDesignColors.textSecondary)
                    Text(session.studioPreset.displayName)
                        .font(PSDesignTypography.headline)
                        .foregroundStyle(PSDesignColors.textPrimary)
                }

                Spacer(minLength: PSDesignSpacing.sm)

                presetSwatches(for: activePack, size: 14)

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PSDesignColors.textTertiary)
            }
            .padding(.vertical, PSDesignSpacing.sm)
            .padding(.horizontal, PSDesignSpacing.md - 4)
            .background(PSDesignColors.elevatedBackground, in: RoundedRectangle(cornerRadius: PSDesignRadius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Studio preset, \(session.studioPreset.displayName)")
        .accessibilityHint(isExpanded ? "Collapse preset options" : "Expand preset options")
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: PSDesignSpacing.md) {
            Text("Preset Categories")
                .psCaption()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: PSDesignSpacing.sm) {
                    ForEach(StudioPresetID.homeCategories) { preset in
                        FilterChip(
                            title: preset.displayName,
                            isSelected: session.studioPreset == preset
                        ) {
                            selectStudioPreset(preset)
                        }
                    }
                }
            }

            Text("Preset Styles")
                .psCaption()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: PSDesignSpacing.sm) {
                    ForEach(
                        activeDefinition.stylePacks(activeStyleID: session.activeCatalogTemplatePackID)
                    ) { pack in
                        stylePackCard(pack)
                    }
                }
            }
        }
        .padding(.horizontal, PSDesignSpacing.xs)
    }

    private func stylePackCard(_ pack: CatalogTemplatePack) -> some View {
        let isActive = session.activeCatalogTemplatePackID == pack.id
        return Button {
            PSDesignHaptics.selection()
            session.studioPreset = StudioPresetLibrary.matchingPreset(for: pack)
            session.applyCatalogTemplate(pack)
            showAppliedToast(pack.id == CatalogTemplateLibrary.appDefaultsID
                ? "Default Studio restored"
                : "Style · \(pack.name)")
        } label: {
            VStack(alignment: .leading, spacing: PSDesignSpacing.sm) {
                HStack(spacing: -5) {
                    presetSwatches(for: pack, size: 18)
                    Spacer(minLength: 0)
                    if isActive {
                        Text("In use")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(PSDesignColors.onPrimaryAccent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(PSDesignColors.primaryButtonFill, in: Capsule())
                    } else {
                        Image(systemName: pack.id == CatalogTemplateLibrary.appDefaultsID
                              ? "house.fill"
                              : pack.channel.systemImage)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(PSDesignColors.textSecondary)
                    }
                }

                Text(pack.name)
                    .font(PSDesignTypography.caption.weight(.bold))
                    .foregroundStyle(PSDesignColors.textPrimary)
                    .lineLimit(1)

                Text(pack.subtitle)
                    .font(PSDesignTypography.footnote)
                    .foregroundStyle(PSDesignColors.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(PSDesignSpacing.sm + 4)
            .frame(width: 148, alignment: .leading)
            .background(PSDesignColors.elevatedBackground, in: RoundedRectangle(cornerRadius: PSDesignRadius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PSDesignRadius.sm, style: .continuous)
                    .stroke(
                        isActive ? PSDesignColors.primaryAccent : PSDesignColors.divider,
                        lineWidth: isActive ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isActive ? "\(pack.name), in use" : "Apply style \(pack.name)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    @ViewBuilder
    private func presetSwatches(for pack: CatalogTemplatePack, size: CGFloat) -> some View {
        HStack(spacing: -4) {
            ForEach(Array(pack.backgroundPreset.hexes.prefix(3).enumerated()), id: \.offset) { _, hex in
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: size, height: size)
                    .overlay(Circle().stroke(PSDesignColors.background, lineWidth: 1.5))
            }
        }
    }

    private func selectStudioPreset(_ preset: StudioPresetID) {
        session.studioPreset = preset
        if preset != .custom {
            session.applyCatalogTemplate(StudioPresetLibrary.definition(for: preset).defaultStylePack)
        }
        showAppliedToast("Studio Preset · \(preset.displayName)")
    }

    private func showAppliedToast(_ message: String) {
        withAnimation(PSDesignMotion.springSoft) {
            appliedToast = message
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation(PSDesignMotion.springSoft) {
                appliedToast = nil
            }
        }
    }
}

/// Legacy name — use `HomeStudioPresetSection`.
typealias HomeWorkflowPresetSection = HomeStudioPresetSection
