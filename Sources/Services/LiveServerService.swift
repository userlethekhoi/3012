import Foundation
import Network
import AVFoundation
import UIKit
import CoreImage

@MainActor
public final class LiveServerService: ObservableObject {
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var port: UInt16 = 5500
    @Published public private(set) var isBackgroundKeepAliveActive: Bool = false
    @Published public private(set) var reloadVersion: Int = 1

    // Share Link Controls (Default OFF — strict owner-only 127.0.0.1 until turned ON)
    @Published public var isShareLinkEnabled: Bool = false {
        didSet {
            shareBox.setEnabled(isShareLinkEnabled)
            if !isShareLinkEnabled {
                closeNonLoopbackConnections()
                recentRemoteViewers.removeAll()
                sharedViewerCount = 0
                activePublicTunnelURL = ""
            }
            refreshLANAddress()
        }
    }
    @Published public var sharePinCode: String = "" {
        didSet {
            let digitsOnly = String(sharePinCode.filter(\.isNumber).prefix(4))
            if digitsOnly != sharePinCode {
                sharePinCode = digitsOnly
                return
            }
            shareBox.setPinCode(digitsOnly)
        }
    }
    @Published public private(set) var sharedViewerCount: Int = 0
    @Published public private(set) var lanIPAddress: String = ""
    @Published public var activePublicTunnelURL: String = ""
    @Published public var isCreatingTunnel: Bool = false

    private var listener: NWListener?
    private let serverQueue = DispatchQueue(label: "com.dev.app3012.liveserver", qos: .userInitiated)
    private var rootDirectory: URL?
    private var silentAudioPlayer: AVAudioPlayer?
    private var recentRemoteViewers: [String: Date] = [:]

    private final class LockedRootBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _url: URL?
        var url: URL? {
            get { lock.lock(); defer { lock.unlock() }; return _url }
            set { lock.lock(); defer { lock.unlock() }; _url = newValue }
        }
    }

    private final class VersionBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _value: Int = 1
        var value: Int {
            get { lock.lock(); defer { lock.unlock() }; return _value }
            set { lock.lock(); defer { lock.unlock() }; _value = newValue }
        }
    }

    private final class LockedShareBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _enabled: Bool = false
        private var _pinCode: String = ""
        private var _nonLoopbackConns: [ObjectIdentifier: NWConnection] = [:]

        var enabled: Bool {
            lock.lock(); defer { lock.unlock() }; return _enabled
        }
        var pinCode: String {
            lock.lock(); defer { lock.unlock() }; return _pinCode
        }
        func setEnabled(_ val: Bool) {
            lock.lock(); _enabled = val; lock.unlock()
        }
        func setPinCode(_ val: String) {
            lock.lock(); _pinCode = val; lock.unlock()
        }
        func registerNonLoopback(_ conn: NWConnection) {
            lock.lock(); _nonLoopbackConns[ObjectIdentifier(conn)] = conn; lock.unlock()
        }
        func unregister(_ conn: NWConnection) {
            lock.lock(); _nonLoopbackConns.removeValue(forKey: ObjectIdentifier(conn)); lock.unlock()
        }
        func closeAllNonLoopback() {
            lock.lock()
            let conns = Array(_nonLoopbackConns.values)
            _nonLoopbackConns.removeAll()
            lock.unlock()
            for c in conns {
                c.cancel()
            }
        }
    }

    private let rootBox = LockedRootBox()
    private let versionBox = VersionBox()
    private let shareBox = LockedShareBox()

    public var serverBaseURLString: String {
        "http://127.0.0.1:\(port)"
    }

    public var shareableLANURLString: String? {
        guard !lanIPAddress.isEmpty else { return nil }
        return "http://\(lanIPAddress):\(port)"
    }

    public init() {
        refreshLANAddress()
    }

    public func refreshLANAddress() {
        lanIPAddress = Self.discoverWiFiLANIPAddress() ?? ""
    }

    private func closeNonLoopbackConnections() {
        shareBox.closeAllNonLoopback()
    }

    public func recordRemoteViewer(host: String) {
        let now = Date()
        recentRemoteViewers[host] = now
        recentRemoteViewers = recentRemoteViewers.filter { now.timeIntervalSince($0.value) < 25 }
        sharedViewerCount = recentRemoteViewers.count
    }

    public func start(serving directory: URL, preferredPort: UInt16 = 5500, keepAliveInBackground: Bool = true) {
        self.rootDirectory = directory
        self.rootBox.url = directory
        refreshLANAddress()
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

            newListener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.port = candidatePort
                        self.isRunning = true
                        self.refreshLANAddress()
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
                guard let self else {
                    connection.cancel()
                    return
                }
                self.handleHTTPConnection(connection)
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
        closeNonLoopbackConnections()
        isShareLinkEnabled = false
        listener?.cancel()
        listener = nil
        isRunning = false
        updateBackgroundKeepAlive(enabled: false)
    }

    public func updateRootDirectory(_ directory: URL) {
        // Hot-swap root directory atomically without restarting NWListener (keeps :5500 stable!)
        self.rootDirectory = directory
        self.rootBox.url = directory
        notifyFileChanged()
    }

    public func notifyFileChanged() {
        reloadVersion += 1
        versionBox.value = reloadVersion
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

    // MARK: - HTTP Request Reader & Share Gatekeeper
    nonisolated private static func endpointHostString(_ endpoint: NWEndpoint) -> String {
        switch endpoint {
        case .hostPort(let host, _):
            switch host {
            case .ipv4(let v4):
                return "\(v4)"
            case .ipv6(let v6):
                return "\(v6)"
            case .name(let name, _):
                return name
            @unknown default:
                return ""
            }
        default:
            return ""
        }
    }

    nonisolated private static func isLoopbackHost(_ rawHost: String) -> Bool {
        let cleaned = rawHost.components(separatedBy: "%").first?.lowercased() ?? ""
        return cleaned == "127.0.0.1"
            || cleaned == "::1"
            || cleaned == "0:0:0:0:0:0:0:1"
            || cleaned == "::ffff:127.0.0.1"
            || cleaned == "localhost"
    }

    nonisolated private func receiveHTTPRequest(
        on connection: NWConnection,
        accumulated: Data,
        completion: @escaping @Sendable (Data?) -> Void
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] chunk, _, isComplete, _ in
            guard let self else {
                completion(nil)
                return
            }
            var buffer = accumulated
            if let chunk {
                buffer.append(chunk)
            }
            let headerEnd = Data("\r\n\r\n".utf8)
            if buffer.range(of: headerEnd) != nil || buffer.count >= 65536 || isComplete {
                completion(buffer.isEmpty ? nil : buffer)
                return
            }
            self.receiveHTTPRequest(on: connection, accumulated: buffer, completion: completion)
        }
    }

    nonisolated private func handleHTTPConnection(_ connection: NWConnection) {
        let remoteHost = Self.endpointHostString(connection.endpoint)
        let isLocalOwner = Self.isLoopbackHost(remoteHost)

        if !isLocalOwner {
            if !shareBox.enabled {
                let deniedHTML = """
                <html><body style="font-family:-apple-system,sans-serif;background:#0f172a;color:#f8fafc;padding:2rem;">
                <h2>3012 Live Preview — Sharing Is Turned Off</h2>
                <p>Chủ dự án đã tắt liên kết chia sẻ Live Server trên ứng dụng 3012 iOS.</p>
                </body></html>
                """
                let resp = Self.buildHTTPResponse(status: "403 Forbidden", contentType: "text/html; charset=utf-8", body: Data(deniedHTML.utf8))
                connection.start(queue: serverQueue)
                connection.send(content: resp, completion: .contentProcessed { _ in connection.cancel() })
                return
            }
            shareBox.registerNonLoopback(connection)
        }

        connection.start(queue: serverQueue)
        receiveHTTPRequest(on: connection, accumulated: Data()) { [weak self] data in
            guard let self else {
                connection.cancel()
                return
            }
            guard let data, let requestText = String(data: data, encoding: .utf8) else {
                self.shareBox.unregister(connection)
                connection.cancel()
                return
            }

            if !isLocalOwner {
                if !self.shareBox.enabled {
                    let resp = Self.buildHTTPResponse(status: "403 Forbidden", contentType: "text/plain", body: Data("403 Sharing Disabled".utf8))
                    connection.send(content: resp, completion: .contentProcessed { _ in
                        self.shareBox.unregister(connection)
                        connection.cancel()
                    })
                    return
                }
                Task { @MainActor [weak self] in
                    self?.recordRemoteViewer(host: remoteHost.isEmpty ? "viewer" : remoteHost)
                }
            }

            let lines = requestText.components(separatedBy: "\r\n")
            let firstLine = lines.first ?? "GET / HTTP/1.1"
            let parts = firstLine.split(separator: " ")
            let rawPath = parts.count >= 2 ? String(parts[1]) : "/"
            let pathComps = rawPath.components(separatedBy: "?")
            let pathOnly = pathComps.first ?? "/"
            let queryStr = pathComps.count > 1 ? pathComps[1] : ""

            // Optional 4-digit PIN gate for external shared viewers (owner 127.0.0.1 always bypasses)
            let requiredPIN = self.shareBox.pinCode
            if !isLocalOwner && !requiredPIN.isEmpty {
                let cookieHeader = lines.first(where: { $0.lowercased().hasPrefix("cookie:") }) ?? ""
                let hasValidCookie = cookieHeader.contains("3012_pin=\(requiredPIN)")
                let queryPIN = Self.extractQueryValue(named: "pin", from: queryStr)

                if pathOnly == "/__3012_auth" || queryPIN == requiredPIN {
                    if queryPIN == requiredPIN {
                        let redirHeaders = [
                            "HTTP/1.1 302 Found",
                            "Location: /",
                            "Set-Cookie: 3012_pin=\(requiredPIN); Path=/; SameSite=Lax",
                            "Content-Length: 0",
                            "Connection: close",
                            "",
                            ""
                        ].joined(separator: "\r\n")
                        connection.send(content: Data(redirHeaders.utf8), completion: .contentProcessed { _ in
                            self.shareBox.unregister(connection)
                            connection.cancel()
                        })
                        return
                    }
                }

                if !hasValidCookie {
                    let pinHTML = Self.buildPinGateHTML(wrongAttempt: queryPIN != nil && !queryPIN!.isEmpty)
                    let resp = Self.buildHTTPResponse(status: "401 Unauthorized", contentType: "text/html; charset=utf-8", body: Data(pinHTML.utf8))
                    connection.send(content: resp, completion: .contentProcessed { _ in
                        self.shareBox.unregister(connection)
                        connection.cancel()
                    })
                    return
                }
            }

            if pathOnly == "/__3012_version" {
                let body = Data("\(self.versionBox.value)".utf8)
                let response = Self.buildHTTPResponse(status: "200 OK", contentType: "text/plain; charset=utf-8", body: body)
                connection.send(content: response, completion: .contentProcessed { _ in
                    self.shareBox.unregister(connection)
                    connection.cancel()
                })
                return
            }

            guard let rootDir = self.rootBox.url else {
                let resp = Self.buildHTTPResponse(status: "503 Service Unavailable", contentType: "text/plain", body: Data("Workspace not mounted".utf8))
                connection.send(content: resp, completion: .contentProcessed { _ in
                    self.shareBox.unregister(connection)
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
                connection.send(content: resp, completion: .contentProcessed { _ in
                    self.shareBox.unregister(connection)
                    connection.cancel()
                })
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
                connection.send(content: resp, completion: .contentProcessed { _ in
                    self.shareBox.unregister(connection)
                    connection.cancel()
                })
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
                connection.send(content: resp, completion: .contentProcessed { _ in
                    self.shareBox.unregister(connection)
                    connection.cancel()
                })
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
                      if (r.status === 403 || r.status === 401) { window.location.reload(); return; }
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
                self.shareBox.unregister(connection)
                connection.cancel()
            })
        }
    }

    nonisolated private static func extractQueryValue(named key: String, from query: String) -> String? {
        for pair in query.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 && String(kv[0]) == key {
                return String(kv[1]).removingPercentEncoding ?? String(kv[1])
            }
        }
        return nil
    }

    nonisolated private static func buildPinGateHTML(wrongAttempt: Bool) -> String {
        """
        <!DOCTYPE html>
        <html lang="vi">
        <head>
          <meta charset="UTF-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1.0" />
          <title>3012 Live Preview — Nhập mã PIN</title>
          <style>
            body { margin:0; min-height:100vh; display:grid; place-items:center; background:#0f172a; color:#f8fafc; font-family:-apple-system,sans-serif; padding:20px; }
            form { max-width:340px; width:100%; background:#1e293b; border:1px solid #334155; border-radius:16px; padding:24px; text-align:center; }
            input { width:100%; box-sizing:border-box; font-size:20px; text-align:center; letter-spacing:8px; padding:12px; border-radius:10px; border:1px solid #475569; background:#0f172a; color:#fff; margin:12px 0; }
            button { width:100%; padding:12px; border-radius:10px; border:0; background:#2563eb; color:#fff; font-weight:700; font-size:15px; cursor:pointer; }
            .err { color:#f87171; font-size:13px; margin-bottom:8px; }
          </style>
        </head>
        <body>
          <form method="GET" action="/__3012_auth">
            <h3>3012 Live Preview</h3>
            <p style="font-size:13px;color:#94a3b8;">Nhập mã PIN 4 số từ chủ dự án để xem.</p>
            \(wrongAttempt ? "<div class='err'>Sai mã PIN, vui lòng thử lại.</div>" : "")
            <input name="pin" type="password" inputmode="numeric" maxlength="4" placeholder="••••" autofocus required />
            <button type="submit">Mở Preview</button>
          </form>
        </body>
        </html>
        """
    }

    nonisolated public static func discoverWiFiLANIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "en1" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, socklen_t(0), NI_NUMERICHOST)
                    let ip = String(cString: hostname)
                    if !ip.isEmpty && !ip.hasPrefix("127.") {
                        address = ip
                        if name == "en0" { break }
                    }
                }
            }
        }
        return address
    }

    public static func generateQRCodeImage(from text: String) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let outputImage = filter.outputImage else { return nil }
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
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
        case "ts", "tsx", "jsx": return "text/plain; charset=utf-8"
        case "json", "map": return "application/json; charset=utf-8"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "avif": return "image/avif"
        case "ico": return "image/x-icon"
        case "woff2": return "font/woff2"
        case "woff": return "font/woff"
        case "ttf": return "font/ttf"
        case "otf": return "font/otf"
        case "mp4": return "video/mp4"
        case "webm": return "video/webm"
        case "mp3": return "audio/mpeg"
        case "pdf": return "application/pdf"
        case "xml": return "application/xml; charset=utf-8"
        case "wasm": return "application/wasm"
        default: return "text/plain; charset=utf-8"
        }
    }

    private static func makeSilentWAVData() -> Data {
        let sampleRate: UInt32 = 8000
        let numSamples: UInt32 = 8000
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
