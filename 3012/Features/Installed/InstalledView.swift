import SwiftUI

struct InstalledView: View {
    @EnvironmentObject private var manager: ManualPatchManager
    @State private var restoreCandidate: InstalledManualPatch?

    var body: some View {
        NavigationStack {
            Group {
                if manager.installed.isEmpty {
                    EmptyStateView(
                        icon: "checkmark.seal.fill",
                        title: "Chưa có patch đã cài",
                        message: "Patch đã xác minh và cài đặt sẽ xuất hiện tại đây cùng trạng thái backup và khôi phục."
                    )
                } else {
                    List(manager.installed) { receipt in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(receipt.name).font(.headline)
                                    Text(receipt.installedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                StatusBadge(title: "ĐÃ BACKUP", color: .green)
                            }
                            Text("\(receipt.fileCount) file · \(ByteCountFormatter.string(fromByteCount: receipt.payloadBytes, countStyle: .file))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Khôi phục file gốc") {
                                restoreCandidate = receipt
                            }
                            .buttonStyle(.bordered)
                            .disabled(manager.isWorking)
                        }
                        .padding(.vertical, 5)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Đã cài")
            .confirmationDialog(
                "Khôi phục file gốc?",
                isPresented: Binding(
                    get: { restoreCandidate != nil },
                    set: { if !$0 { restoreCandidate = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let receipt = restoreCandidate {
                    Button("Khôi phục", role: .destructive) {
                        restoreCandidate = nil
                        manager.restore(receipt)
                    }
                }
                Button("Hủy", role: .cancel) { restoreCandidate = nil }
            } message: {
                Text("3012 chỉ khôi phục nếu file hiện tại vẫn đúng với bản đã patch, tránh ghi đè thay đổi mới của bạn.")
            }
            .alert(
                manager.lastOperationSucceeded ? "Hoàn tất" : "Không thể khôi phục",
                isPresented: Binding(
                    get: { manager.message != nil && !manager.isWorking },
                    set: { if !$0 { manager.message = nil } }
                )
            ) {
                Button("Đóng") { manager.message = nil }
            } message: {
                Text(manager.message ?? "")
            }
        }
    }
}
