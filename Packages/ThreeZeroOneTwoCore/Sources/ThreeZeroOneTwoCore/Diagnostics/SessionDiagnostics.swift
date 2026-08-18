import Foundation

public enum PrivacyRedactor {
    public static func redact(_ input: String) -> String {
        let rules = [
            ("(?i)(bearer\\s+)[A-Za-z0-9._~+\\-/]+=*", "$1<redacted>"),
            ("(?i)((?:token|password|secret|authorization)\\s*[:=]\\s*)[^\\s,;]+", "$1<redacted>"),
            ("[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}", "<redacted>")
        ]
        return rules.reduce(input) { value, rule in
            value.replacingOccurrences(
                of: rule.0,
                with: rule.1,
                options: .regularExpression
            )
        }
    }
}

public struct RotatingTextLogStore {
    public let directory: URL
    public let maximumFileBytes: Int
    public let archiveCount: Int

    private let fileManager: FileManager

    public init(
        directory: URL,
        maximumFileBytes: Int = 256 * 1_024,
        archiveCount: Int = 2,
        fileManager: FileManager = .default
    ) {
        self.directory = directory
        self.maximumFileBytes = max(1, maximumFileBytes)
        self.archiveCount = max(0, archiveCount)
        self.fileManager = fileManager
    }

    public func append(_ line: String) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let current = fileURL(index: 0)
        let data = Data((line + "\n").utf8)
        let currentSize = (try? current.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if currentSize > 0, currentSize + data.count > maximumFileBytes {
            rotate()
        }

        if fileManager.fileExists(atPath: current.path) {
            let handle = try FileHandle(forWritingTo: current)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } else {
            try data.write(to: current, options: .atomic)
        }
    }

    public func removeAll() throws {
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }

    public func fileURL(index: Int) -> URL {
        let name = index == 0 ? "session.log" : "session.\(index).log"
        return directory.appendingPathComponent(name)
    }

    private func rotate() {
        guard archiveCount > 0 else {
            try? fileManager.removeItem(at: fileURL(index: 0))
            return
        }
        for index in stride(from: archiveCount, through: 1, by: -1) {
            let destination = fileURL(index: index)
            let source = fileURL(index: index - 1)
            try? fileManager.removeItem(at: destination)
            if fileManager.fileExists(atPath: source.path) {
                try? fileManager.moveItem(at: source, to: destination)
            }
        }
    }
}
