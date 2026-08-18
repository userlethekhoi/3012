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
            errorMessage = "Không thể đọc package này. File có thể sai định dạng hoặc vượt giới hạn an toàn."
        }
    }

    func clear() {
        preview = nil
        errorMessage = nil
    }
}
