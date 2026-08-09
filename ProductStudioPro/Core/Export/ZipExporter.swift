import Foundation

enum ZipExporter {
    static let imagesFolderName = "Images"
    static let manifestFilename = "manifest.json"

    struct Entry {
        let archivePath: String
        let data: Data
    }

    static func makePackageZip(
        entries: [Entry],
        zipDestination: URL
    ) -> Bool {
        let payload = entries.map { (path: $0.archivePath, data: $0.data) }
        return ZipArchiveWriter.makeZip(entries: payload, zipDestination: zipDestination)
    }

    static func legacyExportZipFilename(productCount: Int) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        let suffix = String((0..<5).map { _ in alphabet.randomElement()! })
        return "ProductStudioPro_\(productCount)_images_\(suffix).zip"
    }

    static func sanitizedProjectZipName(_ projectName: String) -> String {
        let trimmed = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "ProductStudioExport" : trimmed
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        let cleanedScalars = base.unicodeScalars.map { allowed.contains($0) ? $0 : "-" }
        var cleaned = String(String.UnicodeScalarView(cleanedScalars))
        while cleaned.contains("--") { cleaned = cleaned.replacingOccurrences(of: "--", with: "-") }
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "-_ "))
        let finalName = cleaned.isEmpty ? "ProductStudioExport" : cleaned
        return "\(finalName).zip"
    }
}
