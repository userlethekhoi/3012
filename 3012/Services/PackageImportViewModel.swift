import Combine
import Foundation
import ThreeZeroOneTwoCore

@MainActor
final class PackageImportViewModel: ObservableObject {
    @Published var preview: PackagePreview?
    @Published var errorMessage: String?

    func inspect(_ url: URL) {
        let granted = url.startAccessingSecurityScopedResource()
        defer {
            if granted { url.stopAccessingSecurityScopedResource() }
        }
        do {
            preview = try PackagePreviewReader.read(fileURL: url)
            errorMessage = nil
        } catch {
            preview = nil
            errorMessage = AppLocalization.text(
                "error.packageUnreadable",
                fallback: "This package could not be read. It may be malformed or exceed a safety limit."
            )
        }
    }

    func clear() {
        preview = nil
        errorMessage = nil
    }
}
