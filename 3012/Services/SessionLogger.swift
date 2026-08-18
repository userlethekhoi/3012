import Combine
import Foundation

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
    private let maximumFileBytes = 256 * 1_024
    private let fileManager = FileManager.default
    private lazy var logDirectory: URL = {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("3012/Logs", isDirectory: true)
    }()

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
            message: Self.redact(rawMessage)
        )
        entries.append(entry)
        if entries.count > maximumEntries {
            entries.removeFirst(entries.count - maximumEntries)
        }
        persist(entry)
    }

    private func persist(_ entry: SessionLogEntry) {
        do {
            try fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true)
            let current = logDirectory.appendingPathComponent("session.log")
            if ((try? current.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) >= maximumFileBytes {
                rotateFiles()
            }
            let data = Data((Self.format(entry) + "\n").utf8)
            if fileManager.fileExists(atPath: current.path) {
                let handle = try FileHandle(forWritingTo: current)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: current, options: .atomic)
            }
        } catch {
            // Logging must never interrupt patch or restore operations.
        }
    }

    private func rotateFiles() {
        let oldest = logDirectory.appendingPathComponent("session.2.log")
        let previous = logDirectory.appendingPathComponent("session.1.log")
        let current = logDirectory.appendingPathComponent("session.log")
        try? fileManager.removeItem(at: oldest)
        if fileManager.fileExists(atPath: previous.path) {
            try? fileManager.moveItem(at: previous, to: oldest)
        }
        if fileManager.fileExists(atPath: current.path) {
            try? fileManager.moveItem(at: current, to: previous)
        }
    }

    private static func redact(_ input: String) -> String {
        let patterns = [
            ("(?i)(bearer\\s+)[A-Za-z0-9._~+\\-/]+=*", "$1<redacted>"),
            ("(?i)((?:token|password|secret|authorization)\\s*[:=]\\s*)[^\\s,;]+", "$1<redacted>"),
            ("[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}", "<redacted>")
        ]
        return patterns.reduce(input) { value, rule in
            value.replacingOccurrences(
                of: rule.0,
                with: rule.1,
                options: .regularExpression
            )
        }
    }

    private static func format(_ entry: SessionLogEntry) -> String {
        "\(entry.date.formatted(.iso8601)) [\(entry.level.rawValue)] \(entry.message)"
    }
}
