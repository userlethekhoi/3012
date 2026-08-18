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
                        title: "Không có lượt tải",
                        message: "Các package đang tải, tạm dừng hoặc chờ xác minh sẽ được quản lý tại đây."
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
            .navigationTitle("Tải xuống")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showsImporter = true
                    } label: {
                        Label("Nhập package", systemImage: "square.and.arrow.down")
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
                            LabeledContent("Tên", value: preview.name)
                            LabeledContent("Phiên bản", value: preview.version)
                            LabeledContent("Nhà phát hành", value: preview.publisherKeyID)
                            LabeledContent("Số file", value: "\(preview.entryCount)")
                            LabeledContent(
                                "Dung lượng payload",
                                value: ByteCountFormatter.string(
                                    fromByteCount: preview.payloadBytes,
                                    countStyle: .file
                                )
                            )
                            Section {
                                Label(
                                    "Preview chưa xác minh chữ ký. Package chỉ được phép áp dụng sau khi public key production được cấu hình và toàn bộ SHA-256 hợp lệ.",
                                    systemImage: "exclamationmark.shield.fill"
                                )
                                .foregroundStyle(.orange)
                            }
                        }
                        .navigationTitle("Xem trước package")
                        .toolbar {
                            Button("Đóng") { packageImport.clear() }
                        }
                    }
                }
            }
            .alert(
                "Không thể nhập package",
                isPresented: Binding(
                    get: { packageImport.errorMessage != nil },
                    set: { if !$0 { packageImport.clear() } }
                )
            ) {
                Button("Đóng") { packageImport.clear() }
            } message: {
                Text(packageImport.errorMessage ?? "Lỗi không xác định")
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
                        Button("Tạm dừng") { manager.pause(record) }
                    case .paused:
                        Button("Tiếp tục") { manager.resume(record) }
                    case .failed:
                        Button("Thử lại") { manager.retry(record) }
                    default:
                        EmptyView()
                    }
                    Spacer()
                    if record.status != .downloading && record.status != .verifying {
                        Button("Xóa", role: .destructive) { manager.remove(record) }
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

    private func statusTitle(_ status: DownloadStatus) -> String {
        switch status {
        case .queued: return "Đang chờ"
        case .downloading: return "Đang tải"
        case .paused: return "Tạm dừng"
        case .verifying: return "Đang xác minh"
        case .completed: return "Hoàn tất"
        case .failed: return "Lỗi"
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
