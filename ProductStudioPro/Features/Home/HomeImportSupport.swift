import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers

/// Import orchestration shared by the Home screen.
@MainActor
enum HomeImportSupport {
    static func handlePasteOrURLImportButton(
        session: CaptureSessionStore,
        pasteURLText: Binding<String>,
        showPasteOrURLSheet: Binding<Bool>,
        onError: @escaping (String) -> Void,
        onNavigateToQueue: @escaping () -> Void
    ) {
        guard session.activeImport == nil else { return }
        PSDesignHaptics.tap()
        let snapshot = ClipboardURLImageImport.readClipboard()
        if !snapshot.images.isEmpty {
            importUIImageBatch(
                snapshot.images,
                progressMessage: "Importing from clipboard…",
                session: session,
                onError: onError,
                onNavigateToQueue: onNavigateToQueue
            )
            return
        }
        if !snapshot.urls.isEmpty {
            importImagesFromURLs(
                snapshot.urls,
                session: session,
                onError: onError,
                onNavigateToQueue: onNavigateToQueue
            )
            return
        }
        pasteURLText.wrappedValue = snapshot.suggestedURLText
        showPasteOrURLSheet.wrappedValue = true
    }

    static func importFromClipboard(
        session: CaptureSessionStore,
        onError: @escaping (String) -> Void,
        onNavigateToQueue: @escaping () -> Void
    ) {
        guard session.activeImport == nil else { return }
        PSDesignHaptics.tap()
        let snapshot = ClipboardURLImageImport.readClipboard()
        if !snapshot.images.isEmpty {
            importUIImageBatch(
                snapshot.images,
                progressMessage: "Importing from clipboard…",
                session: session,
                onError: onError,
                onNavigateToQueue: onNavigateToQueue
            )
            return
        }
        if !snapshot.urls.isEmpty {
            importImagesFromURLs(
                snapshot.urls,
                session: session,
                onError: onError,
                onNavigateToQueue: onNavigateToQueue
            )
            return
        }
        onError(ClipboardURLImageImportError.nothingToImport.localizedDescription)
    }

    static func importFromPasteSheetURL(
        _ text: String,
        session: CaptureSessionStore,
        onError: @escaping (String) -> Void,
        onNavigateToQueue: @escaping () -> Void
    ) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = ClipboardURLImageImport.parseURL(from: trimmed) else {
            onError(ClipboardURLImageImportError.invalidURL.localizedDescription)
            return false
        }
        importImagesFromURLs([url], session: session, onError: onError, onNavigateToQueue: onNavigateToQueue)
        return true
    }

    static func importUIImageBatch(
        _ images: [UIImage],
        progressMessage: String,
        session: CaptureSessionStore,
        onError: @escaping (String) -> Void,
        onNavigateToQueue: @escaping () -> Void
    ) {
        guard !images.isEmpty else { return }
        let gate = session.gateAddingPhotos(count: images.count)
        if gate.isBlocked {
            onError(gate.userMessage)
            return
        }
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
                    onNavigateToQueue()
                } else {
                    onError(ClipboardURLImageImportError.unsupportedImage.localizedDescription)
                }
                session.clearActiveImport()
            }
        }
    }

    static func importImagesFromURLs(
        _ urls: [URL],
        session: CaptureSessionStore,
        onError: @escaping (String) -> Void,
        onNavigateToQueue: @escaping () -> Void
    ) {
        guard !urls.isEmpty else { return }
        let gate = session.gateAddingPhotos(count: urls.count)
        if gate.isBlocked {
            onError(gate.userMessage)
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
                    onNavigateToQueue()
                } else {
                    onError(ClipboardURLImageImportError.downloadFailed.localizedDescription)
                }
                session.clearActiveImport()
            }
        }
    }

    static func importFiles(
        _ result: Result<[URL], Error>,
        session: CaptureSessionStore,
        onError: @escaping (String) -> Void,
        onNavigateToQueue: @escaping () -> Void
    ) {
        guard case .success(let urls) = result, !urls.isEmpty else { return }
        let gate = session.gateAddingPhotos(count: urls.count)
        if gate.isBlocked {
            onError(gate.userMessage)
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
                    onNavigateToQueue()
                }
                session.clearActiveImport()
            }
        }
    }

    static func importSelectedPhotos(
        _ items: [PhotosPickerItem],
        session: CaptureSessionStore,
        onError: @escaping (String) -> Void,
        onNavigateToQueue: @escaping () -> Void,
        onComplete: @escaping () -> Void
    ) {
        guard !items.isEmpty else { return }
        let gate = session.gateAddingPhotos(count: items.count)
        if gate.isBlocked {
            onError(gate.userMessage)
            onComplete()
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
                    onNavigateToQueue()
                }
                onComplete()
                session.clearActiveImport()
            }
        }
    }
}
