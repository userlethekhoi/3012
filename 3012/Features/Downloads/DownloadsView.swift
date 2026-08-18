import SwiftUI
import ThreeZeroOneTwoCore

struct DownloadsView: View {
    @EnvironmentObject private var manager: BackgroundDownloadManager

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
