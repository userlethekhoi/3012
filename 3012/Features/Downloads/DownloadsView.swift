import SwiftUI
import ThreeZeroOneTwoCore
import UniformTypeIdentifiers

struct DownloadsView: View {
    @EnvironmentObject private var manager: BackgroundDownloadManager
    @StateObject private var packageImport = PackageImportViewModel()
    @State private var showsImporter = false

    var body: some View {
        NavigationStack {
            Group {
                if manager.records.isEmpty {
                    EmptyStateView(
                        icon: "arrow.down.circle.fill",
                        title: "No Downloads",
                        message: "Packages being downloaded, paused, or verified will be managed here."
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(manager.records) { record in
                                downloadCard(record)
                            }
                        }
                        .padding(AppTheme.pagePadding)
                    }
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Downloads")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showsImporter = true
                    } label: {
                        Label("Import Package", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .fileImporter(
                isPresented: $showsImporter,
                allowedContentTypes: [UTType(exportedAs: "app.3012.package")],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    packageImport.inspect(url)
                }
            }
            .sheet(isPresented: Binding(
                get: { packageImport.preview != nil },
                set: { if !$0 { packageImport.clear() } }
            )) {
                if let preview = packageImport.preview {
                    NavigationStack {
                        List {
                            LabeledContent("Name", value: preview.name)
                            LabeledContent("Version", value: preview.version)
                            LabeledContent("Publisher", value: preview.publisherKeyID)
                            LabeledContent("File Count", value: "\(preview.entryCount)")
                            LabeledContent(
                                "Payload Size",
                                value: ByteCountFormatter.string(
                                    fromByteCount: preview.payloadBytes,
                                    countStyle: .file
                                )
                            )
                            Section {
                                Label(
                                    "This preview is not signature verification. A package can be applied only after a production public key is configured and every SHA-256 digest is valid.",
                                    systemImage: "exclamationmark.shield.fill"
                                )
                                .foregroundStyle(.orange)
                            }
                        }
                        .navigationTitle("Package Preview")
                        .toolbar {
                            Button("Close") { packageImport.clear() }
                        }
                    }
                }
            }
            .alert(
                "Package Import Failed",
                isPresented: Binding(
                    get: { packageImport.errorMessage != nil },
                    set: { if !$0 { packageImport.clear() } }
                )
            ) {
                Button("Close") { packageImport.clear() }
            } message: {
                Text(packageImport.errorMessage ?? "Unknown Error")
            }
        }
    }

    private func downloadCard(_ record: DownloadRecord) -> some View {
        PremiumCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.packageID)
                            .font(.headline)
                            .lineLimit(1)
                        Text(byteDescription(record))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(title: statusTitle(record.status), color: statusColor(record.status))
                }

                if record.expectedSize > 0 && record.status != .completed {
                    ProgressView(value: min(Double(record.bytesReceived) / Double(record.expectedSize), 1))
                        .tint(AppTheme.accent)
                }

                if let reason = record.failureReason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                HStack {
                    switch record.status {
                    case .downloading:
                        Button("Pause") { manager.pause(record) }
                    case .paused:
                        Button("Resume") { manager.resume(record) }
                    case .failed:
                        Button("Retry") { manager.retry(record) }
                    default:
                        EmptyView()
                    }
                    Spacer()
                    if record.status != .downloading && record.status != .verifying {
                        Button("Delete", role: .destructive) { manager.remove(record) }
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func byteDescription(_ record: DownloadRecord) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let received = formatter.string(fromByteCount: record.bytesReceived)
        let total = formatter.string(fromByteCount: record.expectedSize)
        return "\(received) / \(total)"
    }

    private func statusTitle(_ status: DownloadStatus) -> LocalizedStringKey {
        switch status {
        case .queued: return "Queued"
        case .downloading: return "Downloading"
        case .paused: return "Paused"
        case .verifying: return "Verifying"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }

    private func statusColor(_ status: DownloadStatus) -> Color {
        switch status {
        case .completed: return .green
        case .failed: return .red
        case .paused: return .orange
        default: return AppTheme.accent
        }
    }
}
