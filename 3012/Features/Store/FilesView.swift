import SwiftUI

struct FilesView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Standard Files Access", systemImage: "folder.badge.gearshape")
                        .font(.headline)
                    Text("Select a folder through the iOS Files picker to grant 3012 access. Direct app-container browsing will appear only when a verified provider is available.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Available Now") {
                    NavigationLink {
                        ManualPatchView()
                    } label: {
                        Label("Open Manual Patch", systemImage: "externaldrive.badge.plus")
                    }
                }
            }
            .navigationTitle("Files")
        }
    }
}
