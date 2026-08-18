import SwiftUI

private struct ContainerDirectoryEntry: Identifiable {
    let url: URL
    let isDirectory: Bool
    let isSymbolicLink: Bool
    let byteCount: Int64

    var id: String { url.path }
}

struct ContainerDirectoryView: View {
    let rootURL: URL
    let directoryURL: URL
    let title: String

    @State private var entries: [ContainerDirectoryEntry] = []
    @State private var errorMessage: String?

    init(rootURL: URL, directoryURL: URL? = nil, title: String) {
        self.rootURL = rootURL.standardizedFileURL
        self.directoryURL = (directoryURL ?? rootURL).standardizedFileURL
        self.title = title
    }

    var body: some View {
        Group {
            if let errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(AppTheme.failure)
                    Text("Folder Unavailable")
                        .font(.headline)
                    Text(verbatim: errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(32)
            } else if entries.isEmpty {
                EmptyStateView(
                    icon: "folder",
                    title: "Empty Folder",
                    message: "No visible items were found in this folder."
                )
            } else {
                List(entries) { entry in
                    if entry.isDirectory && !entry.isSymbolicLink {
                        NavigationLink {
                            ContainerDirectoryView(
                                rootURL: rootURL,
                                directoryURL: entry.url,
                                title: entry.url.lastPathComponent
                            )
                        } label: {
                            entryLabel(entry)
                        }
                    } else {
                        entryLabel(entry)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: directoryURL) { loadEntries() }
    }

    private func entryLabel(_ entry: ContainerDirectoryEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.isSymbolicLink
                ? "link"
                : (entry.isDirectory ? "folder.fill" : "doc.fill"))
                .foregroundStyle(entry.isDirectory ? AppTheme.accent : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: entry.url.lastPathComponent)
                    .lineLimit(1)
                if !entry.isDirectory {
                    Text(ByteCountFormatter.string(fromByteCount: entry.byteCount, countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func loadEntries() {
        let rootPath = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        guard directoryURL.path == rootURL.path || directoryURL.path.hasPrefix(rootPath) else {
            errorMessage = AppLocalization.text(
                "error.pathOutsideLease",
                fallback: "The requested path is outside the active container lease."
            )
            return
        }
        do {
            let keys: Set<URLResourceKey> = [
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
                .nameKey
            ]
            entries = try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            ).prefix(5_000).map { url in
                let values = try? url.resourceValues(forKeys: keys)
                return ContainerDirectoryEntry(
                    url: url.standardizedFileURL,
                    isDirectory: values?.isDirectory ?? false,
                    isSymbolicLink: values?.isSymbolicLink ?? false,
                    byteCount: Int64(values?.fileSize ?? 0)
                )
            }.sorted {
                if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                return $0.url.lastPathComponent.localizedCaseInsensitiveCompare(
                    $1.url.lastPathComponent
                ) == .orderedAscending
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
