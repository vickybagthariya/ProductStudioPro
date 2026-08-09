import SwiftUI

/// Progressive product identification — barcode, manual SKU, and product name.
struct CaptureProductIdentificationSection: View {
    @ObservedObject var session: CaptureSessionStore
    let showsScanner: Bool
    let showManualEntry: Bool
    let captureUsesCustomName: Bool
    let nameEntryHint: String?
    let recentBarcodes: [String]
    let lastUsedUPC: String
    let onScanResult: (String) -> Void
    let onOpenScanner: () -> Void
    let onManualUPC: () -> Void
    let onManualName: () -> Void
    let onUseLastUPC: () -> Void
    let onRecentBarcode: (String) -> Void
    @Binding var manualUPCText: String
    @Binding var manualNameText: String
    var manualUPCFocused: FocusState<Bool>.Binding
    var manualNameFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    let onToggleNameMode: () -> Void
    let queueInFlight: Bool
    var scannerEpoch: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: PSDesignSpacing.sm) {
            Text("Identify Product")
                .psHeadline()

            if showsScanner {
                scannerBlock
            } else if showManualEntry || session.imageNamingMode == .manualInput {
                manualEntryBlock
            } else {
                optionPicker
            }
        }
        .animation(PSDesignMotion.springSoft, value: showsScanner)
        .animation(PSDesignMotion.springSoft, value: showManualEntry)
    }

    private var scannerBlock: some View {
        VStack(spacing: PSDesignSpacing.sm) {
            RoundedRectangle(cornerRadius: PSDesignRadius.md, style: .continuous)
                .fill(Color.black)
                .frame(maxWidth: .infinity)
                .frame(height: 240)
                .overlay {
                    BarcodeScannerView { code in
                        onScanResult(code)
                    }
                    .id(scannerEpoch)
                }
                .clipShape(RoundedRectangle(cornerRadius: PSDesignRadius.md, style: .continuous))

            Text("Option 1 · Point at the barcode — scanning is automatic")
                .psCaption()
                .frame(maxWidth: .infinity, alignment: .leading)

            alternateOptionsDivider

            optionRow(
                number: 2,
                title: "Enter UPC or SKU",
                systemImage: "123.rectangle",
                action: onManualUPC
            )

            optionRow(
                number: 3,
                title: "Enter Product Name",
                systemImage: "character.cursor.ibeam",
                action: onManualName
            )

            shortcutsSection
        }
    }

    private var optionPicker: some View {
        VStack(spacing: PSDesignSpacing.sm - 2) {
            optionRow(
                number: 1,
                title: "Scan Barcode",
                subtitle: "Fastest — automatic recognition",
                systemImage: "barcode.viewfinder",
                action: onOpenScanner,
                emphasized: true
            )

            alternateOptionsDivider

            optionRow(
                number: 2,
                title: "Enter UPC or SKU",
                subtitle: "Type the product code manually",
                systemImage: "123.rectangle",
                action: onManualUPC
            )

            alternateOptionsDivider

            optionRow(
                number: 3,
                title: "Enter Product Name",
                subtitle: "Use any custom label",
                systemImage: "character.cursor.ibeam",
                action: onManualName
            )

            shortcutsSection
        }
    }

    private var alternateOptionsDivider: some View {
        Text("or")
            .psFootnote()
            .frame(maxWidth: .infinity)
    }

    private func optionRow(
        number: Int,
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        action: @escaping () -> Void,
        emphasized: Bool = false
    ) -> some View {
        Button(action: {
            PSDesignHaptics.tap()
            action()
        }) {
            HStack(spacing: PSDesignSpacing.md) {
                Text("\(number)")
                    .font(PSDesignTypography.caption.weight(.bold))
                    .foregroundStyle(emphasized ? PSDesignColors.onPrimaryAccent : PSDesignColors.primaryAccent)
                    .frame(width: 24, height: 24)
                    .background(
                        (emphasized ? PSDesignColors.primaryAccent : PSDesignColors.primaryAccent.opacity(0.12)),
                        in: Circle()
                    )

                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(emphasized ? PSDesignColors.onPrimaryAccent : PSDesignColors.primaryAccent)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(emphasized ? PSDesignTypography.headline : PSDesignTypography.headline)
                        .foregroundStyle(emphasized ? PSDesignColors.onPrimaryAccent : PSDesignColors.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(PSDesignTypography.caption)
                            .foregroundStyle(emphasized ? PSDesignColors.onPrimaryAccent.opacity(0.85) : PSDesignColors.textSecondary)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(emphasized ? PSDesignColors.onPrimaryAccent.opacity(0.85) : PSDesignColors.textTertiary)
            }
            .padding(PSDesignSpacing.sm + 2)
            .background(
                emphasized ? PSDesignColors.primaryButtonFill : PSDesignColors.elevatedBackground,
                in: RoundedRectangle(cornerRadius: PSDesignRadius.sm, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var shortcutsSection: some View {
        if !lastUsedUPC.isEmpty {
            GhostButton("Use last: \(lastUsedUPC)", systemImage: "clock.arrow.circlepath") {
                onUseLastUPC()
            }
        }

        if !recentBarcodes.isEmpty {
            VStack(alignment: .leading, spacing: PSDesignSpacing.xs) {
                Text("Recent scans")
                    .psFootnote()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: PSDesignSpacing.sm) {
                        ForEach(recentBarcodes.prefix(8), id: \.self) { code in
                            CategoryChip(title: code) {
                                onRecentBarcode(code)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var manualEntryBlock: some View {
        VStack(spacing: PSDesignSpacing.sm) {
            if let nameEntryHint {
                Text(nameEntryHint)
                    .font(PSDesignTypography.footnote)
                    .foregroundStyle(PSDesignColors.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if session.imageNamingMode == .manualInput && !showManualEntry {
                TextField("Image name", text: $manualNameText)
                    .textFieldStyle(.roundedBorder)
                    .focused(manualNameFocused)
                    .submitLabel(.done)
                    .onSubmit { onSubmit() }
            } else {
                TextField(
                    captureUsesCustomName ? "Product name" : "UPC or SKU",
                    text: $manualUPCText
                )
                .keyboardType(captureUsesCustomName ? .default : .numberPad)
                .textInputAutocapitalization(captureUsesCustomName ? .words : .never)
                .autocorrectionDisabled(!captureUsesCustomName)
                .textFieldStyle(.roundedBorder)
                .focused(manualUPCFocused)
                .submitLabel(.done)
                .onSubmit { onSubmit() }
                .id(captureUsesCustomName ? "nameField" : "upcField")

                HStack {
                    GhostButton(
                        captureUsesCustomName ? "Enter UPC" : "Use product name",
                        systemImage: captureUsesCustomName ? "123.rectangle" : "character.cursor.ibeam"
                    ) {
                        onToggleNameMode()
                    }
                    Spacer()
                    GhostButton("Scan barcode", systemImage: "barcode.viewfinder") {
                        onOpenScanner()
                    }
                }
            }

            PrimaryButton(
                session.imageNamingMode == .manualInput && !showManualEntry ? "Use This Name" : "Add to Queue",
                systemImage: PSDesignIcons.queue,
                isDisabled: queueInFlight,
                isLoading: queueInFlight
            ) {
                onSubmit()
            }
        }
    }
}
