import SwiftUI

/// Collapsible secondary import paths beneath the primary Import Photos action.
struct HomeMoreImportOptions: View {
    let sources: [HomeImportSourceOption]
    var isImporting: Bool

    @State private var isExpanded = false

    private var visibleSources: [HomeImportSourceOption] {
        sources.filter(\.isAvailable)
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(PSDesignColors.divider)
                .padding(.vertical, PSDesignSpacing.sm)

            disclosureToggle

            if isExpanded, !visibleSources.isEmpty {
                expandedSourceList
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(PSDesignMotion.springSoft, value: isExpanded)
    }

    private var disclosureToggle: some View {
        Button {
            guard !isImporting else { return }
            PSDesignHaptics.selection()
            isExpanded.toggle()
        } label: {
            HStack(spacing: PSDesignSpacing.sm) {
                Text("More Import Options")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PSDesignColors.textSecondary)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PSDesignColors.textTertiary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                Spacer(minLength: 0)
            }
            .padding(.vertical, PSDesignSpacing.sm - 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isImporting)
        .opacity(isImporting ? PSDesignMotion.disabledOpacity : 1)
        .accessibilityLabel("More Import Options")
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }

    private var expandedSourceList: some View {
        VStack(spacing: 0) {
            ForEach(visibleSources) { source in
                Button {
                    PSDesignHaptics.tap()
                    isExpanded = false
                    source.action()
                } label: {
                    HStack(spacing: PSDesignSpacing.sm) {
                        Image(systemName: source.systemImage)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PSDesignColors.primaryAccent)
                            .frame(width: 22, alignment: .center)
                        Text(source.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(PSDesignColors.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, PSDesignSpacing.sm)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, PSDesignSpacing.xs)
    }
}
