import Foundation
import Network
import AVFoundation
import UIKit

@MainActor
public final class LiveServerService: ObservableObject {
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var port: UInt16 = 5500
    @Published public private(set) var isBackgroundKeepAliveActive: Bool = false
    @Published public private(set) var reloadVersion: Int = 1

    private var listener: NWListener?
    private let serverQueue = DispatchQueue(label: "com.dev.app3012.liveserver", qos: .userInitiated)
    private var rootDirectory: URL?
    private var silentAudioPlayer: AVAudioPlayer?
    private final class VersionBox: @unchecked Sendable {
        var value: Int = 1
    }
    private let versionBox = VersionBox()

    public var serverBaseURLString: String {
        "http://127.0.0.1:\(port)"
    }

    public init() {}

    public func start(serving directory: URL, preferredPort: UInt16 = 5500, keepAliveInBackground: Bool = true) {
        self.rootDirectory = directory
        if isRunning {
            notifyFileChanged()
            updateBackgroundKeepAlive(enabled: keepAliveInBackground)
            return
        }
        tryStartListener(on: preferredPort, attemptsRemaining: 10, keepAlive: keepAliveInBackground)
    }

    private func tryStartListener(on candidatePort: UInt16, attemptsRemaining: Int, keepAlive: Bool) {
        guard let nwPort = NWEndpoint.Port(rawValue: candidatePort) else { return }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let newListener = try NWListener(using: params, on: nwPort)
            let capturedRoot = self.rootDirectory

            newListener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.port = candidatePort
                        self.isRunning = true
                        self.updateBackgroundKeepAlive(enabled: keepAlive)
                    case .failed:
                        newListener.cancel()
                        self.isRunning = false
                        if attemptsRemaining > 0 {
                            self.tryStartListener(on: candidatePort + 1, attemptsRemaining: attemptsRemaining - 1, keepAlive: keepAlive)
                        }
                    default:
                        break
                    }
                }
            }

            newListener.newConnectionHandler = { [weak self] connection in
                guard let self, let dir = capturedRoot else {
                    connection.cancel()
                    return
                }
                self.handleHTTPConnection(connection, rootDir: dir)
            }

            self.listener = newListener
            newListener.start(queue: serverQueue)
        } catch {
            if attemptsRemaining > 0 {
                tryStartListener(on: candidatePort + 1, attemptsRemaining: attemptsRemaining - 1, keepAlive: keepAlive)
            }
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        updateBackgroundKeepAlive(enabled: false)
    }

    public func updateRootDirectory(_ directory: URL) {
        let wasRunning = isRunning
        let keepAlive = isBackgroundKeepAliveActive
        if wasRunning {
            stop()
            start(serving: directory, preferredPort: port, keepAliveInBackground: keepAlive)
        } else {
            self.rootDirectory = directory
        }
    }

    public func notifyFileChanged() {
        reloadVersion += 1
        versionBox.value = reloadVersion
    }

    nonisolated public static func encodeRelativePath(_ relativePath: String) -> String {
        let segments = relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { seg -> String in
                let s = String(seg)
                return s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? s
            }
        return segments.joined(separator: "/")
    }

    nonisolated private static func firstHTMLFile(in directory: URL) -> URL? {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        return entries
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .first { url in
                let ext = url.pathExtension.lowercased()
                return ext == "html" || ext == "htm"
            }
    }

    nonisolated private static func buildDirectoryListingHTML(for directory: URL, relativePath: String) -> String {
        let entries = ((try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []).sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }

        let baseRel = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let listItems: String = entries.map { url in
            let name = url.lastPathComponent
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let display = isDir ? "\(name)/" : name
            let hrefRel = baseRel.isEmpty ? name : "\(baseRel)/\(name)"
            let hrefEncoded = "/" + encodeRelativePath(hrefRel)
            let escapedDisplay = display
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            return "<li><a href=\"\(hrefEncoded)\">\(escapedDisplay)</a></li>"
        }.joined(separator: "\n")

        let titlePath = baseRel.isEmpty ? "/" : "/\(baseRel)"
        return """
        <!DOCTYPE html>
        <html lang="vi">
        <head>
          <meta charset="UTF-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1.0" />
          <title>3012 Live Server — \(titlePath)</title>
          <style>
            body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; background: #0f172a; color: #e2e8f0; padding: 1.5rem; line-height: 1.6; }
            h2 { color: #10b981; margin-bottom: 0.5rem; }
            ul { list-style: none; padding: 0; }
            li { margin: 0.4rem 0; }
            a { color: #38bdf8; text-decoration: none; font-family: monospace; font-size: 1rem; }
          </style>
        </head>
        <body>
          <h2>3012 Live Server — \(titlePath)</h2>
          <p>Không có tệp <code>index.html</code>. Chọn tệp trong thư mục:</p>
          <ul>\(listItems.isEmpty ? "<li><em>(Thư mục trống)</em></li>" : listItems)</ul>
        </body>
        </html>
        """
    }

    public func openInSafari(relativePath: String = "index.html") {
        let encoded = Self.encodeRelativePath(relativePath)
        let urlString = encoded.isEmpty ? serverBaseURLString : "http://localhost:\(port)/\(encoded)"
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }

    public func updateBackgroundKeepAlive(enabled: Bool) {
        if enabled && isRunning {
            guard silentAudioPlayer == nil else {
                isBackgroundKeepAliveActive = true
                return
            }
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, options: [.mixWithOthers])
                try session.setActive(true)
                let wavData = Self.makeSilentWAVData()
                let player = try AVAudioPlayer(data: wavData)
                player.numberOfLoops = -1
                player.volume = 0.0
                player.play()
                self.silentAudioPlayer = player
                self.isBackgroundKeepAliveActive = true
            } catch {
                self.isBackgroundKeepAliveActive = false
            }
        } else {
            silentAudioPlayer?.stop()
            silentAudioPlayer = nil
            isBackgroundKeepAliveActive = false
        }
    }

    nonisolated private func handleHTTPConnection(_ connection: NWConnection, rootDir: URL) {
        connection.start(queue: serverQueue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            guard let self, let data, let requestText = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }

            let firstLine = requestText.components(separatedBy: "\r\n").first ?? "GET / HTTP/1.1"
            let parts = firstLine.split(separator: " ")
            let rawPath = parts.count >= 2 ? String(parts[1]) : "/"
            let pathOnly = rawPath.components(separatedBy: "?").first ?? "/"

            if pathOnly == "/__3012_version" {
                let body = Data("\(self.versionBox.value)".utf8)
                let response = Self.buildHTTPResponse(status: "200 OK", contentType: "text/plain; charset=utf-8", body: body)
                connection.send(content: response, completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return
            }

            let decodedPath = pathOnly.removingPercentEncoding ?? pathOnly
            let relative = decodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

            // Prevent path traversal outside workspace root (resolving /var vs /private/var symlinks)
            let resolvedRoot = rootDir.resolvingSymlinksInPath().standardizedFileURL
            let targetURL = (relative.isEmpty ? resolvedRoot : resolvedRoot.appendingPathComponent(relative))
                .resolvingSymlinksInPath()
                .standardizedFileURL
            let rootPath = resolvedRoot.path
            let isWithinRoot = (targetURL.path == rootPath) || targetURL.path.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/")
            guard isWithinRoot else {
                let forbidden = Data("403 Forbidden".utf8)
                let resp = Self.buildHTTPResponse(status: "403 Forbidden", contentType: "text/plain", body: forbidden)
                connection.send(content: resp, completion: .contentProcessed { _ in connection.cancel() })
                return
            }

            let fm = FileManager.default
            var resolvedURL = targetURL
            var isDir: ObjCBool = false
            var directoryToList: URL? = nil

            if fm.fileExists(atPath: resolvedURL.path, isDirectory: &isDir), isDir.boolValue {
                let indexURL = resolvedURL.appendingPathComponent("index.html")
                if fm.fileExists(atPath: indexURL.path) {
                    resolvedURL = indexURL
                } else if let fallbackHTML = Self.firstHTMLFile(in: resolvedURL) {
                    resolvedURL = fallbackHTML
                } else {
                    directoryToList = resolvedURL
                }
            } else if relative == "index.html", !fm.fileExists(atPath: resolvedURL.path) {
                if let fallbackHTML = Self.firstHTMLFile(in: resolvedRoot) {
                    resolvedURL = fallbackHTML
                } else {
                    directoryToList = resolvedRoot
                }
            }

            if let listDir = directoryToList {
                let listingHTML = Self.buildDirectoryListingHTML(for: listDir, relativePath: relative)
                let resp = Self.buildHTTPResponse(status: "200 OK", contentType: "text/html; charset=utf-8", body: Data(listingHTML.utf8))
                connection.send(content: resp, completion: .contentProcessed { _ in connection.cancel() })
                return
            }

            guard var fileData = try? Data(contentsOf: resolvedURL) else {
                let notFoundHTML = """
                <html><body style="font-family:sans-serif;background:#0f172a;color:#e2e8f0;padding:2rem;">
                <h2>3012 Live Server — 404 Not Found</h2>
                <p>File <code>/\(relative)</code> does not exist in the current workspace.</p>
                </body></html>
                """
                let resp = Self.buildHTTPResponse(status: "404 Not Found", contentType: "text/html; charset=utf-8", body: Data(notFoundHTML.utf8))
                connection.send(content: resp, completion: .contentProcessed { _ in connection.cancel() })
                return
            }

            let ext = resolvedURL.pathExtension.lowercased()
            let mime = Self.mimeType(for: ext)

            if ext == "html" || ext == "htm", var htmlStr = String(data: fileData, encoding: .utf8) {
                let liveReloadSnippet = """
                <script>
                (function(){
                  let currentVer = null;
                  setInterval(async () => {
                    try {
                      const r = await fetch('/__3012_version', { cache: 'no-store' });
                      const v = await r.text();
                      if (currentVer === null) { currentVer = v; }
                      else if (v !== currentVer) { window.location.reload(); }
                    } catch (_) {}
                  }, 450);
                })();
                </script>
                """
                if let range = htmlStr.range(of: "</body>", options: .caseInsensitive) {
                    htmlStr.replaceSubrange(range, with: liveReloadSnippet + "\n</body>")
                } else {
                    htmlStr += liveReloadSnippet
                }
                fileData = Data(htmlStr.utf8)
            }

            let response = Self.buildHTTPResponse(status: "200 OK", contentType: mime, body: fileData)
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    nonisolated private static func buildHTTPResponse(status: String, contentType: String, body: Data) -> Data {
        let headers = [
            "HTTP/1.1 \(status)",
            "Content-Type: \(contentType)",
            "Content-Length: \(body.count)",
            "Cache-Control: no-store, no-cache, must-revalidate",
            "Access-Control-Allow-Origin: *",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")
        var full = Data(headers.utf8)
        full.append(body)
        return full
    }

    nonisolated private static func mimeType(for ext: String) -> String {
        switch ext {
        case "html", "htm": return "text/html; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "js", "mjs": return "application/javascript; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "ico": return "image/x-icon"
        case "wasm": return "application/wasm"
        default: return "text/plain; charset=utf-8"
        }
    }

    private static func makeSilentWAVData() -> Data {
        let sampleRate: UInt32 = 8000
        let numSamples: UInt32 = 8000 // 1 second of 16-bit mono silence
        let dataSize: UInt32 = numSamples * 2
        let riffSize: UInt32 = 36 + dataSize

        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        data.append(withUnsafeBytes(of: riffSize.littleEndian) { Data($0) })
        data.append(contentsOf: "WAVEfmt ".utf8)
        let fmtSize: UInt32 = 16
        let audioFormat: UInt16 = 1
        let numChannels: UInt16 = 1
        let byteRate: UInt32 = sampleRate * 2
        let blockAlign: UInt16 = 2
        let bitsPerSample: UInt16 = 16
        data.append(withUnsafeBytes(of: fmtSize.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: audioFormat.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: numChannels.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: sampleRate.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })
        data.append(contentsOf: "data".utf8)
        data.append(withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })
        data.append(Data(count: Int(dataSize)))
        return data
    }
}
