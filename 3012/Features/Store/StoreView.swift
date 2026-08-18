import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var deviceService: DeviceProfileService
    @EnvironmentObject private var logger: SessionLogger
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
                    technicalRow("Provider", deviceService.compatibility.providerName)
                    technicalRow("Bundle ID", deviceService.profile.bundleIdentifier)
                    Label(
                        "3012 currently writes only inside folders explicitly selected through Files.",
                        systemImage: "hand.raised.fill"
                    )
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
            }
            .sheet(isPresented: $showsLogs) {
                SessionLogView()
            }
            .task {
                deviceService.refresh(logger: logger)
            }
        }
    }

    private var supportRow: some View {
        HStack(spacing: 14) {
            Image(systemName: deviceService.compatibility.level.symbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(deviceService.compatibility.level.color)
                .frame(width: 42, height: 42)
                .background(
                    deviceService.compatibility.level.color.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(deviceService.compatibility.level.title)
                    .font(.headline)
                Text(deviceService.compatibility.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
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
