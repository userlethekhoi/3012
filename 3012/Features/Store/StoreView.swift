import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var deviceService: DeviceProfileService
    @EnvironmentObject private var logger: SessionLogger
    @EnvironmentObject private var access: DeviceAccessCoordinator
    @State private var showsLogs = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    supportRow
                }

                Section("Device") {
                    technicalRow("Name", deviceService.profile.deviceName)
                    technicalRow("Model", deviceService.profile.machineIdentifier)
                    technicalRow("Architecture", deviceService.profile.architecture)
                }

                Section("System") {
                    technicalRow("iOS", deviceService.profile.systemVersion)
                    technicalRow("Build", deviceService.profile.buildNumber)
                }

                Section("Access") {
                    technicalRow("Provider", access.selectedProvider.rawValue)
                    technicalRow("Bundle ID", deviceService.profile.bundleIdentifier)
                    if access.directContainerAccessAvailable {
                        Label(
                            "Container browsing is read-only in this milestone.",
                            systemImage: "eye.fill"
                        )
                    } else {
                        Label(
                            "3012 currently writes only inside folders explicitly selected through Files.",
                            systemImage: "hand.raised.fill"
                        )
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("3012")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showsLogs = true
                    } label: {
                        Label("Session Logs", systemImage: "terminal.fill")
                    }
                }
            }
            .refreshable {
                deviceService.refresh(logger: logger)
                await access.refresh(profile: deviceService.profile, logger: logger)
            }
            .sheet(isPresented: $showsLogs) {
                SessionLogView()
            }
            .task {
                deviceService.refresh(logger: logger)
                await access.refresh(profile: deviceService.profile, logger: logger)
            }
        }
    }

    private var supportRow: some View {
        HStack(spacing: 14) {
            Image(systemName: supportLevel.symbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(supportLevel.color)
                .frame(width: 42, height: 42)
                .background(
                    supportLevel.color.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(supportLevel.title)
                    .font(.headline)
                Text(supportDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var supportLevel: SupportLevel {
        access.capabilities.isEmpty ? .unavailable : .supported
    }

    private var supportDetail: LocalizedStringKey {
        access.directContainerAccessAvailable
            ? "Read-only app-container access is available."
            : "Manual patching through Files is available. Direct app-container access is not enabled in this build."
    }

    private func technicalRow(_ title: LocalizedStringKey, _ value: String) -> some View {
        LabeledContent {
            Text(value)
                .font(.technicalValue)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        } label: {
            Text(title)
        }
    }
}
