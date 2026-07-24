import SwiftUI

/// Move selected queue items into an existing session folder or a newly created one.
struct AddToSessionFolderSheet: View {
    @EnvironmentObject private var session: CaptureSessionStore
    @Environment(\.dismiss) private var dismiss

    let productIDs: Set<UUID>
    var onFinished: ((String) -> Void)?

    @State private var newFolderName = ""
    @State private var moveError: String?
    @State private var isMoving = false

    private var destinations: [NamedCatalogSession] {
        session.catalogSessions.filter { $0.id != session.activeCatalogSessionID }
    }

    private var selectedCount: Int {
        session.products.filter { productIDs.contains($0.id) }.count
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if destinations.isEmpty {
                        Text("No other folders yet. Create one below.")
                            .font(DS.TypeScale.caption)
                            .foregroundStyle(DS.ColorToken.secondaryLabel)
                    } else {
                        ForEach(destinations) { item in
                            Button {
                                move(to: item.id, displayName: item.name)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "folder")
                                        .foregroundStyle(DS.ColorToken.accent)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name)
                                            .font(DS.TypeScale.rowTitle)
                                            .foregroundStyle(DS.ColorToken.label)
                                        Text("\(session.catalogSessionProductCount(id: item.id)) photos")
                                            .font(DS.TypeScale.caption)
                                            .foregroundStyle(DS.ColorToken.secondaryLabel)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.right.circle")
                                        .foregroundStyle(DS.ColorToken.secondaryLabel)
                                }
                            }
                            .disabled(isMoving || selectedCount == 0)
                        }
                    }
                } header: {
                    Text("Move \(selectedCount) photo\(selectedCount == 1 ? "" : "s") to…")
                } footer: {
                    Text("Photos leave the current queue and appear in the chosen folder. Soft limit is \(CaptureSessionStore.CatalogSessionLimits.softQueueCap) per folder.")
                }

                Section("New folder") {
                    HStack(spacing: 10) {
                        TextField("Folder name", text: $newFolderName)
                            .textInputAutocapitalization(.words)
                            .disabled(isMoving)
                        Button("Create & move") {
                            createAndMove()
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .disabled(isMoving || selectedCount == 0)
                    }
                }

                if let moveError {
                    Section {
                        Text(moveError)
                            .font(DS.TypeScale.caption)
                            .foregroundStyle(DS.ColorToken.error)
                    }
                }
            }
            .navigationTitle("Add to Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isMoving)
                }
            }
            .overlay {
                if isMoving {
                    ProgressView("Moving…")
                        .padding(18)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func createAndMove() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = session.createCatalogSessionFolder(named: name.isEmpty ? nil : name)
        let label = session.catalogSessions.first(where: { $0.id == id })?.name ?? "New folder"
        move(to: id, displayName: label)
    }

    private func move(to sessionID: UUID, displayName: String) {
        guard !isMoving else { return }
        isMoving = true
        moveError = nil
        let result = session.moveProducts(ids: productIDs, toSession: sessionID)
        isMoving = false
        switch result {
        case .success(let count):
            onFinished?("Moved \(count) to \(displayName)")
            dismiss()
        case .failure(let error):
            moveError = error.errorDescription
        }
    }
}
