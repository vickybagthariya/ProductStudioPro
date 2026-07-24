import SwiftUI

struct PasteOrURLImportSheet: View {
    @Binding var urlText: String
    let onImport: () -> Void
    let onCancel: () -> Void

    @FocusState private var urlFieldFocused: Bool
    @State private var isImporting = false

    private var trimmedURL: String {
        urlText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canImport: Bool {
        !trimmedURL.isEmpty && !isImporting
    }

    var body: some View {
        NavigationStack {
            AppScreenScaffold(
                title: "Paste Image or URL",
                subtitle: "Like remove.bg — paste a link or copy an image first, then import.",
                showsHome: false,
                layout: .scroll
            ) {
                DSCard {
                    VStack(alignment: .leading, spacing: DS.Space.stack) {
                        Text("Image URL")
                            .font(DS.TypeScale.caption.weight(.semibold))
                            .foregroundStyle(DS.ColorToken.secondaryLabel)

                        TextField("https://example.com/product.jpg", text: $urlText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .focused($urlFieldFocused)
                            .dsSemanticTextField()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(DS.ColorToken.backgroundTertiary, in: RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))

                        Text("Tip: copy a photo in Safari or Photos, then tap Upload from URL or Clipboard on the home screen — no typing needed.")
                            .font(DS.TypeScale.caption)
                            .foregroundStyle(DS.ColorToken.secondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Button {
                    guard canImport else { return }
                    isImporting = true
                    onImport()
                } label: {
                    HStack(spacing: 8) {
                        if isImporting {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(DS.ColorToken.onAccent)
                                .scaleEffect(0.85)
                        }
                        Label(isImporting ? "Importing…" : "Import", systemImage: "arrow.down.circle.fill")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canImport)
                .opacity(canImport ? 1 : DS.Motion.disabledOpacity)
                .saturation(canImport ? 1 : DS.Motion.disabledSaturation)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                        .foregroundStyle(DS.ColorToken.accent)
                        .buttonStyle(.plainPressable)
                }
            }
            .onAppear { urlFieldFocused = true }
        }
    }
}
