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
                        title: "No Installed Patches",
                        message: "Verified installed patches will appear here with backup and restore status."
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
                                StatusBadge(title: "BACKED UP", color: .green)
                            }
                            HStack(spacing: 4) {
                                Text(verbatim: "\(receipt.fileCount)")
                                Text("files")
                                Text(verbatim: "· \(ByteCountFormatter.string(fromByteCount: receipt.payloadBytes, countStyle: .file))")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            Button("Restore Original Files") {
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
            .navigationTitle("Installed & Restore")
            .confirmationDialog(
                "Restore Original Files?",
                isPresented: Binding(
                    get: { restoreCandidate != nil },
                    set: { if !$0 { restoreCandidate = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let receipt = restoreCandidate {
                    Button("Restore", role: .destructive) {
                        restoreCandidate = nil
                        manager.restore(receipt)
                    }
                }
                Button("Cancel", role: .cancel) { restoreCandidate = nil }
            } message: {
                Text("3012 restores only when the current file still matches the patched version, preventing newer changes from being overwritten.")
            }
            .alert(
                manager.lastOperationSucceeded ? "Completed" : "Restore Failed",
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
}
