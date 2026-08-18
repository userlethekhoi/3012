import SwiftUI

struct PatchesView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Patch Sources") {
                    NavigationLink {
                        ManualPatchView()
                    } label: {
                        featureLabel(
                            "Manual Patch",
                            detail: "Use large local files without uploading them to a server.",
                            symbol: "externaldrive.badge.plus"
                        )
                    }

                    featureLabel(
                        "Online Catalog",
                        detail: "No production catalog is configured yet.",
                        symbol: "network"
                    )
                }

                Section("Activity") {
                    NavigationLink {
                        DownloadsView()
                    } label: {
                        Label("Downloads", systemImage: "arrow.down.circle")
                    }
                    NavigationLink {
                        InstalledView()
                    } label: {
                        Label("Installed & Restore", systemImage: "clock.arrow.circlepath")
                    }
                }
            }
            .navigationTitle("Patches")
        }
    }

    private func featureLabel(_ title: LocalizedStringKey, detail: LocalizedStringKey, symbol: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}
