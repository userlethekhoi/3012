import SwiftUI

struct FilesView: View {
    @EnvironmentObject private var deviceService: DeviceProfileService
    @EnvironmentObject private var access: DeviceAccessCoordinator
    @EnvironmentObject private var logger: SessionLogger

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
                            ForEach(access.containers) { container in
                                NavigationLink {
                                    ContainerDirectoryView(
                                        rootURL: container.rootURL,
                                        title: container.bundleIdentifier
                                    )
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(verbatim: container.bundleIdentifier)
                                            .font(.technicalValue)
                                        Text(verbatim: container.rootURL.lastPathComponent)
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                    }
                                }
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
                        Text("Select a folder through the iOS Files picker to grant 3012 access. Direct app-container browsing will appear only when a verified provider is available.")
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
}
