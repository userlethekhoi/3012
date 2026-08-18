import SwiftUI
import UIKit

struct SessionLogView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var logger: SessionLogger

    var body: some View {
        NavigationStack {
            Group {
                if logger.entries.isEmpty {
                    EmptyStateView(
                        icon: "terminal",
                        title: "No Session Logs",
                        message: "Runtime diagnostics will appear here. Sensitive values are redacted before storage."
                    )
                } else {
                    List(logger.entries) { entry in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(entry.level.rawValue)
                                    .foregroundStyle(color(for: entry.level))
                                Spacer()
                                Text(entry.date.formatted(date: .omitted, time: .standard))
                                    .foregroundStyle(.secondary)
                            }
                            Text(entry.message)
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                        }
                        .font(.sessionLog)
                        .padding(.vertical, 3)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Session Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        UIPasteboard.general.string = logger.exportText
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    ShareLink(item: logger.exportText) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    private func color(for level: SessionLogEntry.Level) -> Color {
        switch level {
        case .info: return AppTheme.accent
        case .warning: return AppTheme.warning
        case .error: return AppTheme.failure
        }
    }
}
