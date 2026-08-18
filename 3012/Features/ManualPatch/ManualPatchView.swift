import SwiftUI
import ThreeZeroOneTwoCore
import UniformTypeIdentifiers

struct ManualPatchView: View {
    @EnvironmentObject private var manager: ManualPatchManager
    @State private var showsTargetPicker = false
    @State private var showsFilePicker = false
    @State private var showsConfirmation = false

    var body: some View {
        Form {
            Section("Thông tin") {
                TextField("Tên patch", text: $manager.patchName)
                LabeledContent("Chế độ", value: "Cục bộ · Không tải server")
            }

            Section("Thư mục đích") {
                Button {
                    showsTargetPicker = true
                } label: {
                    Label(
                        manager.targetURL?.lastPathComponent ?? "Chọn thư mục được phép patch",
                        systemImage: "folder.badge.gearshape"
                    )
                }
                Text("3012 chỉ ghi bên trong thư mục bạn chọn qua Files. Hãy chọn đúng thư mục gốc để relative path bên dưới khớp chính xác.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    showsFilePicker = true
                } label: {
                    Label("Thêm file thay thế", systemImage: "doc.badge.plus")
                }
                ForEach(manager.items) { item in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "doc.fill")
                                .foregroundStyle(AppTheme.accent)
                            Text(item.sourceURL.lastPathComponent)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Spacer()
                            Text(ByteCountFormatter.string(
                                fromByteCount: item.byteCount,
                                countStyle: .file
                            ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        TextField(
                            "Relative path, ví dụ Documents/file.bin",
                            text: Binding(
                                get: { item.relativePath },
                                set: { manager.updatePath(id: item.id, path: $0) }
                            )
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.caption.monospaced())

                        Picker(
                            "Thao tác",
                            selection: Binding(
                                get: { item.operation },
                                set: { manager.updateOperation(id: item.id, operation: $0) }
                            )
                        ) {
                            Text("Thay file có sẵn").tag(PackageOperation.replaceFile)
                            Text("Tạo file mới").tag(PackageOperation.createFile)
                        }
                        .pickerStyle(.segmented)

                        Button("Bỏ file", role: .destructive) {
                            manager.removeItem(id: item.id)
                        }
                        .font(.caption.weight(.semibold))
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("File patch (\(manager.items.count))")
            } footer: {
                Text("File lớn được đọc theo từng khối. App tạo package tạm, xác minh SHA-256, backup file gốc và xóa package tạm sau khi hoàn tất.")
            }

            Section {
                Button {
                    showsConfirmation = true
                } label: {
                    HStack {
                        if manager.isWorking { ProgressView() }
                        Text(manager.isWorking ? "Đang patch…" : "Kiểm tra và patch")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(manager.isWorking || manager.items.isEmpty || manager.targetURL == nil)
            } footer: {
                Text("Không đóng app hoặc ngắt kết nối Files khi đang patch. Nếu một bước thất bại, transaction sẽ rollback những file đã thay đổi.")
            }
        }
        .navigationTitle("Patch thủ công")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showsTargetPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                manager.selectTarget(url)
            }
        }
        .fileImporter(
            isPresented: $showsFilePicker,
            allowedContentTypes: [.data],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                manager.addFiles(urls)
            }
        }
        .confirmationDialog(
            "Xác nhận patch thủ công",
            isPresented: $showsConfirmation,
            titleVisibility: .visible
        ) {
            Button("Tạo backup và patch") { manager.apply() }
            Button("Hủy", role: .cancel) {}
        } message: {
            Text("3012 sẽ xác minh toàn bộ file, tạo journal và backup trước khi thay đổi thư mục đích.")
        }
        .alert(
            manager.lastOperationSucceeded ? "Hoàn tất" : "3012",
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
