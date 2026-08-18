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
            Section("Information") {
                TextField("Patch Name", text: $manager.patchName)
                LabeledContent("Mode") { Text("Local · No Server Upload") }
            }

            Section("Target Folder") {
                Button {
                    showsTargetPicker = true
                } label: {
                    if let targetURL = manager.targetURL {
                        Label {
                            Text(verbatim: targetURL.lastPathComponent)
                        } icon: {
                            Image(systemName: "folder.badge.gearshape")
                        }
                    } else {
                        Label("Choose a Folder to Patch", systemImage: "folder.badge.gearshape")
                    }
                }
                Text("3012 writes only inside the folder selected through Files. Choose the correct root folder so the relative paths below match exactly.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    showsFilePicker = true
                } label: {
                    Label("Add Replacement Files", systemImage: "doc.badge.plus")
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
                            "Relative path, for example Documents/file.bin",
                            text: Binding(
                                get: { item.relativePath },
                                set: { manager.updatePath(id: item.id, path: $0) }
                            )
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.caption.monospaced())

                        Picker(
                            "Operation",
                            selection: Binding(
                                get: { item.operation },
                                set: { manager.updateOperation(id: item.id, operation: $0) }
                            )
                        ) {
                            Text("Replace Existing File").tag(PackageOperation.replaceFile)
                            Text("Create New File").tag(PackageOperation.createFile)
                        }
                        .pickerStyle(.segmented)

                        Button("Remove File", role: .destructive) {
                            manager.removeItem(id: item.id)
                        }
                        .font(.caption.weight(.semibold))
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                HStack(spacing: 4) {
                    Text("Patch Files")
                    Text(verbatim: "(\(manager.items.count))")
                }
            } footer: {
                Text("Large files are streamed in chunks. The app creates a temporary package, verifies SHA-256, backs up originals, and removes the temporary package when finished.")
            }

            Section {
                Button {
                    showsConfirmation = true
                } label: {
                    HStack {
                        if manager.isWorking { ProgressView() }
                        if manager.isWorking {
                            Text("Patching…")
                        } else {
                            Text("Verify and Patch")
                        }
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(manager.isWorking || manager.items.isEmpty || manager.targetURL == nil)
            } footer: {
                Text("Do not close the app or disconnect Files while patching. If a step fails, the transaction rolls back files already changed.")
            }
        }
        .navigationTitle("Manual Patch")
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
            "Confirm Manual Patch",
            isPresented: $showsConfirmation,
            titleVisibility: .visible
        ) {
            Button("Back Up and Patch") { manager.apply() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("3012 verifies every file and creates a journal and backup before changing the target folder.")
        }
        .alert(
            manager.lastOperationSucceeded ? "Completed" : "3012",
            isPresented: Binding(
                get: { manager.message != nil && !manager.isWorking },
                set: { if !$0 { manager.message = nil } }
            )
        ) {
            Button("Close") { manager.message = nil }
        } message: {
            Text(manager.message ?? "")
        }
    }
}
