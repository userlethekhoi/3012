import SwiftUI

struct FilesView: View {
    @EnvironmentObject private var deviceService: DeviceProfileService
    @EnvironmentObject private var access: DeviceAccessCoordinator
    @EnvironmentObject private var logger: SessionLogger
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List {
                if access.directContainerAccessAvailable {
                    Section("App Containers") {
                        if access.isScanning {
                            HStack {
                                ProgressView()
                                Text("Scanning Containers…")
                            }
                        } else if access.containers.isEmpty {
                            Button {
                                access.scanContainers(logger: logger)
                            } label: {
                                Label("Scan App Containers", systemImage: "arrow.clockwise")
                            }
                        } else {
                            ForEach(filteredContainers) { container in
                                NavigationLink {
                                    ContainerDirectoryView(
                                        rootURL: container.rootURL,
                                        title: container.bundleIdentifier
                                    )
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(verbatim: container.displayName)
                                            .font(.headline)
                                        Text(verbatim: container.bundleIdentifier)
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                        Text(verbatim: "\(container.rootURL.lastPathComponent) · \(container.discoverySources.joined(separator: ", "))")
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            if filteredContainers.isEmpty && !searchText.isEmpty {
                                Text("No matching app containers.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    Label {
                        if access.directContainerAccessAvailable {
                            Text("Read-Only Device Access")
                        } else {
                            Text("Standard Files Access")
                        }
                    } icon: {
                        Image(systemName: "folder.badge.gearshape")
                    }
                    .font(.headline)

                    if access.directContainerAccessAvailable {
                        Text("Application containers are exposed read-only until device validation and transaction integration are complete.")
                    } else {
                        containerStatusText
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Section("Available Now") {
                    NavigationLink {
                        ManualPatchView()
                    } label: {
                        Label("Open Manual Patch", systemImage: "externaldrive.badge.plus")
                    }
                }
            }
            .navigationTitle("Files")
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: Text("Search apps, Bundle IDs, or UUIDs")
            )
            .task {
                await access.refresh(profile: deviceService.profile, logger: logger)
            }
            .refreshable {
                await access.refresh(profile: deviceService.profile, logger: logger)
                if access.directContainerAccessAvailable {
                    access.scanContainers(logger: logger)
                }
            }
            .alert("Container Access", isPresented: Binding(
                get: { access.errorMessage != nil },
                set: { if !$0 { access.errorMessage = nil } }
            )) {
                Button("Close") { access.errorMessage = nil }
            } message: {
                Text(access.errorMessage ?? "")
            }
        }
    }

    private var filteredContainers: [AppContainerRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return access.containers }
        return access.containers.filter { container in
            container.displayName.localizedCaseInsensitiveContains(query)
                || container.bundleIdentifier.localizedCaseInsensitiveContains(query)
                || container.rootURL.lastPathComponent.localizedCaseInsensitiveContains(query)
                || container.discoverySources.contains {
                    $0.localizedCaseInsensitiveContains(query)
                }
        }
    }

    private var containerStatusText: Text {
        Text(verbatim: access.statusDetail)
    }
}
