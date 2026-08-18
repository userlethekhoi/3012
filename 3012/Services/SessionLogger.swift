import Combine
import Foundation
import ThreeZeroOneTwoCore

struct SessionLogEntry: Identifiable, Codable {
    enum Level: String, Codable {
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
    }

    let id: UUID
    let date: Date
    let level: Level
    let message: String
}

@MainActor
final class SessionLogger: ObservableObject {
    @Published private(set) var entries: [SessionLogEntry] = []

    private let maximumEntries = 400
    private let fileManager = FileManager.default
    private lazy var logDirectory: URL = {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("3012/Logs", isDirectory: true)
    }()
    private lazy var logStore = RotatingTextLogStore(directory: logDirectory)

    init() {
        info("3012 session started.")
    }

    func info(_ message: String) { append(.info, message) }
    func warning(_ message: String) { append(.warning, message) }
    func error(_ message: String) { append(.error, message) }

    var exportText: String {
        entries.map(Self.format).joined(separator: "\n")
    }

    func clear() {
        entries.removeAll()
        try? fileManager.removeItem(at: logDirectory)
        info("Session log cleared.")
    }

    private func append(_ level: SessionLogEntry.Level, _ rawMessage: String) {
        let entry = SessionLogEntry(
            id: UUID(),
            date: Date(),
            level: level,
            message: PrivacyRedactor.redact(rawMessage)
        )
        entries.append(entry)
        if entries.count > maximumEntries {
            entries.removeFirst(entries.count - maximumEntries)
        }
        persist(entry)
    }

    private func persist(_ entry: SessionLogEntry) {
        do {
            try logStore.append(Self.format(entry))
        } catch {
            // Logging must never interrupt patch or restore operations.
        }
    }

    private static func format(_ entry: SessionLogEntry) -> String {
        "\(entry.date.formatted(.iso8601)) [\(entry.level.rawValue)] \(entry.message)"
    }
}
