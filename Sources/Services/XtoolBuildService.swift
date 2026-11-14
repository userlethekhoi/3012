import Foundation
import SwiftUI
import ZIPFoundation

public enum XtoolBuildMode: String, CaseIterable, Identifiable, Codable {
    case privateSSHVPS = "privateSSHVPS"
    case offlineGitHubActions = "offlineGitHubActions"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .privateSSHVPS:
            return L10n.tr("VPS SSH Cá nhân (xtool CLI)", "Private SSH VPS (xtool CLI)")
        case .offlineGitHubActions:
            return L10n.tr("GitHub Actions + Đóng gói .zip", "GitHub Actions + .zip Export")
        }
    }

    public var subtitle: String {
        switch self {
        case .privateSSHVPS:
            return L10n.tr(
                "Đẩy SwiftPM + xtool.yml lên VPS Linux/macOS qua SSH để build .ipa trực tiếp",
                "Push SwiftPM + xtool.yml to your SSH VPS to compile .ipa via xtool"
            )
        case .offlineGitHubActions:
            return L10n.tr(
                "Sinh sẵn .github/workflows/build-xtool-ipa.yml & gói .zip sạch trong packages/",
                "Generate .github/workflows/build-xtool-ipa.yml & export clean .zip in packages/"
            )
        }
    }
}

public enum XtoolTemplateKind: String, CaseIterable, Identifiable {
    case swiftUIApp = "swiftUIApp"
    case swiftUIWidgetExtension = "swiftUIWidgetExtension"
    case modMenuHostApp = "modMenuHostApp"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .swiftUIApp:
            return L10n.tr("SwiftUI iOS App (xtool + SwiftPM)", "SwiftUI iOS App (xtool + SwiftPM)")
        case .swiftUIWidgetExtension:
            return L10n.tr("SwiftUI App + Widget Extension", "SwiftUI App + Widget Extension")
        case .modMenuHostApp:
            return L10n.tr("Host App + Runtime .dylib Loader (Non-JB)", "Host App + Runtime .dylib Loader (Non-JB)")
        }
    }

    public var summary: String {
        switch self {
        case .swiftUIApp:
            return L10n.tr(
                "Cấu trúc chuẩn xtool: Package.swift (.library) + xtool.yml (version: 1) + SwiftUI App không cần Xcode.",
                "Standard xtool layout: Package.swift (.library) + xtool.yml (version: 1) + SwiftUI App without Xcode."
            )
        case .swiftUIWidgetExtension:
            return L10n.tr(
                "Kèm thêm target Widget Extension trong Package.swift và mục extensions: trong xtool.yml.",
                "Adds a secondary Widget Extension target in Package.swift wired under extensions: in xtool.yml."
            )
        case .modMenuHostApp:
            return L10n.tr(
                "Ứng dụng SwiftUI kèm bộ nạp dlopen(\"Frameworks/ModMenu.dylib\") phục vụ test tweak/mod Non-JB.",
                "SwiftUI host app with runtime dlopen(\"Frameworks/ModMenu.dylib\") loader for Non-JB tweak testing."
            )
        }
    }
}

public struct XtoolArtifactItem: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let size: Int64
    public let localURL: URL

    public init(name: String, size: Int64, localURL: URL) {
        self.id = localURL.path
        self.name = name
        self.size = size
        self.localURL = localURL
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

public struct XtoolManifestSummary: Equatable {
    public var productName: String
    public var bundleID: String
    public var infoPath: String
    public var entitlementsPath: String
    public var hasXtoolYML: Bool
    public var hasPackageSwift: Bool
    public var extensionsCount: Int

    public init(
        productName: String = "",
        bundleID: String = "",
        infoPath: String = "",
        entitlementsPath: String = "",
        hasXtoolYML: Bool = false,
        hasPackageSwift: Bool = false,
        extensionsCount: Int = 0
    ) {
        self.productName = productName
        self.bundleID = bundleID
        self.infoPath = infoPath
        self.entitlementsPath = entitlementsPath
        self.hasXtoolYML = hasXtoolYML
        self.hasPackageSwift = hasPackageSwift
        self.extensionsCount = extensionsCount
    }
}

public struct XtoolInjectionOptions: Sendable {
    public var bundleIDOverride: String
    public var displayNameOverride: String
    public var stripOldCodeSignature: Bool

    public init(
        bundleIDOverride: String = "",
        displayNameOverride: String = "",
        stripOldCodeSignature: Bool = true
    ) {
        self.bundleIDOverride = bundleIDOverride
        self.displayNameOverride = displayNameOverride
        self.stripOldCodeSignature = stripOldCodeSignature
    }
}

public enum XtoolMachOPatchStatus: Equatable, Sendable {
    case inserted(sliceCount: Int, loadPath: String)
    case alreadyPresent(loadPath: String)
}

public enum XtoolInjectionError: LocalizedError {
    case invalidIPA(String)
    case dylibNotFound(String)
    case executableMissing(String)
    case invalidMachO(String)
    case insufficientHeaderPadding(available: Int, required: Int)
    case packagingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidIPA(let msg): return msg
        case .dylibNotFound(let msg): return msg
        case .executableMissing(let msg): return msg
        case .invalidMachO(let msg): return msg
        case .insufficientHeaderPadding(let available, let required):
            return L10n.tr(
                "Không đủ khoảng trống header Mach-O để chèn LC_LOAD_DYLIB (còn \(available) bytes, cần \(required) bytes).",
                "Insufficient Mach-O header padding for LC_LOAD_DYLIB (available: \(available) bytes, required: \(required) bytes)."
            )
        case .packagingFailed(let msg): return msg
        }
    }
}

@MainActor
public final class XtoolBuildService: ObservableObject {
    @Published public var buildMode: XtoolBuildMode {
        didSet { UserDefaults.standard.set(buildMode.rawValue, forKey: "3012.xtool.buildMode") }
    }
    @Published public var overrideBundleID: String {
        didSet { UserDefaults.standard.set(overrideBundleID, forKey: "3012.xtool.overrideBundleID") }
    }
    @Published public var overrideDisplayName: String {
        didSet { UserDefaults.standard.set(overrideDisplayName, forKey: "3012.xtool.overrideDisplayName") }
    }
    @Published public var stripOldCodeSignature: Bool {
        didSet { UserDefaults.standard.set(stripOldCodeSignature, forKey: "3012.xtool.stripSignature") }
    }

    @Published public private(set) var isBuilding: Bool = false
    @Published public private(set) var isInjecting: Bool = false
    @Published public private(set) var buildStatusText: String = "Sẵn sàng build xtool / Non-JB .ipa"
    @Published public var buildLog: String = ""
    @Published public private(set) var downloadedArtifacts: [XtoolArtifactItem] = []

    private var activeTask: Task<Void, Never>?

    public init() {
        if let rawMode = UserDefaults.standard.string(forKey: "3012.xtool.buildMode"),
           let mode = XtoolBuildMode(rawValue: rawMode) {
            self.buildMode = mode
        } else {
            self.buildMode = .offlineGitHubActions
        }
        self.overrideBundleID = UserDefaults.standard.string(forKey: "3012.xtool.overrideBundleID") ?? ""
        self.overrideDisplayName = UserDefaults.standard.string(forKey: "3012.xtool.overrideDisplayName") ?? ""
        if UserDefaults.standard.object(forKey: "3012.xtool.stripSignature") != nil {
            self.stripOldCodeSignature = UserDefaults.standard.bool(forKey: "3012.xtool.stripSignature")
        } else {
            self.stripOldCodeSignature = true
        }
    }

    // MARK: - Workspace Detection & Inspection
    public func isXtoolWorkspace(_ rootURL: URL) -> Bool {
        let fm = FileManager.default
        let xtoolYML = rootURL.appendingPathComponent("xtool.yml")
        if fm.fileExists(atPath: xtoolYML.path) {
            return true
        }
        let pkgSwift = rootURL.appendingPathComponent("Package.swift")
        if fm.fileExists(atPath: pkgSwift.path),
           let pkgText = try? String(contentsOf: pkgSwift, encoding: .utf8) {
            if pkgText.contains(".iOS(") || pkgText.contains("SwiftUI") || pkgText.contains("UIKit") {
                return true
            }
            let sourcesDir = rootURL.appendingPathComponent("Sources", isDirectory: true)
            if fm.fileExists(atPath: sourcesDir.path) {
                return true
            }
        }
        return false
    }

    public func inspectWorkspace(_ rootURL: URL) -> XtoolManifestSummary {
        let fm = FileManager.default
        let xtoolURL = rootURL.appendingPathComponent("xtool.yml")
        let packageURL = rootURL.appendingPathComponent("Package.swift")
        var summary = XtoolManifestSummary(
            hasXtoolYML: fm.fileExists(atPath: xtoolURL.path),
            hasPackageSwift: fm.fileExists(atPath: packageURL.path)
        )

        if let ymlText = try? String(contentsOf: xtoolURL, encoding: .utf8) {
            let lines = ymlText.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
            var inExtensions = false
            var extCount = 0
            for rawLine in lines {
                let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
                let isIndented = rawLine.hasPrefix(" ") || rawLine.hasPrefix("\t")

                if !isIndented {
                    inExtensions = trimmed.hasPrefix("extensions:")
                } else if inExtensions && trimmed.hasPrefix("- product:") {
                    extCount += 1
                }

                if !isIndented, let val = Self.yamlScalarValue(forKey: "product", in: trimmed) {
                    summary.productName = val
                } else if !isIndented, let val = Self.yamlScalarValue(forKey: "bundleID", in: trimmed) {
                    summary.bundleID = val
                } else if !isIndented, let val = Self.yamlScalarValue(forKey: "infoPath", in: trimmed) {
                    summary.infoPath = val
                } else if !isIndented, let val = Self.yamlScalarValue(forKey: "entitlementsPath", in: trimmed) {
                    summary.entitlementsPath = val
                }
            }
            summary.extensionsCount = extCount
        }

        if summary.productName.isEmpty,
           let pkgText = try? String(contentsOf: packageURL, encoding: .utf8) {
            let libraries = Self.extractSwiftPackageLibraryNames(from: pkgText)
            if let first = libraries.first {
                summary.productName = first
            } else if let pkgName = Self.extractSwiftPackageName(from: pkgText) {
                summary.productName = pkgName
            }
        }
        return summary
    }

    public func refreshLocalPackages(in workspaceRoot: URL) {
        let packagesDir = workspaceRoot.appendingPathComponent("packages", isDirectory: true)
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: packagesDir,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            downloadedArtifacts = []
            return
        }

        let valid = urls.compactMap { url -> XtoolArtifactItem? in
            let lower = url.lastPathComponent.lowercased()
            guard lower.hasSuffix(".ipa") || lower.hasSuffix(".dylib") || lower.hasSuffix(".zip") else {
                return nil
            }
            let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            return XtoolArtifactItem(name: url.lastPathComponent, size: size, localURL: url)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        downloadedArtifacts = valid
    }

    // MARK: - 1-Tap xtool Project Scaffolding
    @discardableResult
    public func scaffoldTemplate(
        kind: XtoolTemplateKind,
        appName rawName: String,
        bundleID rawBundleID: String,
        in workspace: WorkspaceManager
    ) -> URL? {
        let cleanName = Self.sanitizeSwiftIdentifier(rawName, fallback: "App3012")
        let cleanBundleID = rawBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "com.dev.\(cleanName.lowercased())"
            : rawBundleID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let root = workspace.rootURL
        let workflowYML = Self.githubWorkflowTemplate(productName: cleanName)
        var files: [(relPath: String, content: String)] = []
        var primaryFile = "Sources/\(cleanName)/\(cleanName)App.swift"

        switch kind {
        case .swiftUIApp:
            let packageSwift = """
            // swift-tools-version: 5.10
            import PackageDescription

            let package = Package(
                name: "\(cleanName)",
                platforms: [
                    .iOS(.v17)
                ],
                products: [
                    // xtool builds apps from .library products instead of executable targets
                    .library(name: "\(cleanName)", targets: ["\(cleanName)"])
                ],
                targets: [
                    .target(name: "\(cleanName)")
                ]
            )
            """

            let xtoolYML = """
            version: 1
            bundleID: \(cleanBundleID)
            product: \(cleanName)
            infoPath: Info.plist
            """

            let infoPlist = Self.standardAppInfoPlist(displayName: cleanName)

            let appSwift = """
            import SwiftUI

            @main
            struct \(cleanName)App: App {
                var body: some Scene {
                    WindowGroup {
                        ContentView()
                    }
                }
            }
            """

            let contentSwift = """
            import SwiftUI

            struct ContentView: View {
                @State private var tapCount: Int = 0

                var body: some View {
                    NavigationStack {
                        VStack(spacing: 16) {
                            Image(systemName: "hammer.circle.fill")
                                .font(.system(size: 56))
                                .foregroundStyle(.blue)
                            Text("\(cleanName)")
                                .font(.title.bold())
                            Text("Built with 3012 IDE + xtool SwiftPM")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Button("Tap Count: \\(tapCount)") {
                                tapCount += 1
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding()
                        .navigationTitle("\(cleanName)")
                    }
                }
            }
            """

            files = [
                ("Package.swift", packageSwift + "\n"),
                ("xtool.yml", xtoolYML + "\n"),
                ("Info.plist", infoPlist + "\n"),
                ("Sources/\(cleanName)/\(cleanName)App.swift", appSwift + "\n"),
                ("Sources/\(cleanName)/ContentView.swift", contentSwift + "\n"),
                (".github/workflows/build-xtool-ipa.yml", workflowYML)
            ]

        case .swiftUIWidgetExtension:
            let widgetName = "\(cleanName)Widget"
            let packageSwift = """
            // swift-tools-version: 5.10
            import PackageDescription

            let package = Package(
                name: "\(cleanName)",
                platforms: [
                    .iOS(.v17)
                ],
                products: [
                    .library(name: "\(cleanName)", targets: ["\(cleanName)"]),
                    .library(name: "\(widgetName)", targets: ["\(widgetName)"])
                ],
                targets: [
                    .target(name: "\(cleanName)"),
                    .target(name: "\(widgetName)")
                ]
            )
            """

            let xtoolYML = """
            version: 1
            bundleID: \(cleanBundleID)
            product: \(cleanName)
            infoPath: Info.plist
            extensions:
              - product: \(widgetName)
                infoPath: \(widgetName)-Info.plist
            """

            let appPlist = Self.standardAppInfoPlist(displayName: cleanName)
            let widgetPlist = Self.widgetExtensionInfoPlist(extensionName: widgetName)

            let appSwift = """
            import SwiftUI

            @main
            struct \(cleanName)App: App {
                var body: some Scene {
                    WindowGroup {
                        ContentView()
                    }
                }
            }
            """

            let contentSwift = """
            import SwiftUI

            struct ContentView: View {
                var body: some View {
                    VStack(spacing: 12) {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.indigo)
                        Text("\(cleanName) + Widget")
                            .font(.title2.bold())
                        Text("Check your Home Screen widgets after installing via xtool.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
            }
            """

            let widgetSwift = """
            import WidgetKit
            import SwiftUI

            struct StatusEntry: TimelineEntry {
                let date: Date
            }

            struct StatusProvider: TimelineProvider {
                func placeholder(in context: Context) -> StatusEntry {
                    StatusEntry(date: .now)
                }

                func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
                    completion(StatusEntry(date: .now))
                }

                func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
                    let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
                    completion(Timeline(entries: [StatusEntry(date: .now)], policy: .after(next)))
                }
            }

            @main
            struct \(widgetName): Widget {
                var body: some WidgetConfiguration {
                    StaticConfiguration(kind: "\(widgetName)", provider: StatusProvider()) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(cleanName)")
                                .font(.headline)
                            Text(entry.date, style: .time)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .containerBackground(.fill.tertiary, for: .widget)
                    }
                    .configurationDisplayName("\(cleanName) Widget")
                    .description("Built with xtool & 3012 IDE.")
                }
            }
            """

            files = [
                ("Package.swift", packageSwift + "\n"),
                ("xtool.yml", xtoolYML + "\n"),
                ("Info.plist", appPlist + "\n"),
                ("\(widgetName)-Info.plist", widgetPlist + "\n"),
                ("Sources/\(cleanName)/\(cleanName)App.swift", appSwift + "\n"),
                ("Sources/\(cleanName)/ContentView.swift", contentSwift + "\n"),
                ("Sources/\(widgetName)/\(widgetName).swift", widgetSwift + "\n"),
                (".github/workflows/build-xtool-ipa.yml", workflowYML)
            ]

        case .modMenuHostApp:
            let packageSwift = """
            // swift-tools-version: 5.10
            import PackageDescription

            let package = Package(
                name: "\(cleanName)",
                platforms: [
                    .iOS(.v17)
                ],
                products: [
                    .library(name: "\(cleanName)", targets: ["\(cleanName)"])
                ],
                targets: [
                    .target(name: "\(cleanName)")
                ]
            )
            """

            let xtoolYML = """
            version: 1
            bundleID: \(cleanBundleID)
            product: \(cleanName)
            infoPath: Info.plist
            """

            let infoPlist = Self.standardAppInfoPlist(displayName: cleanName)

            let appSwift = """
            import SwiftUI
            import Darwin

            @main
            struct \(cleanName)App: App {
                init() {
                    DylibRuntimeLoader.loadDefaultEmbeddedDylib()
                }

                var body: some Scene {
                    WindowGroup {
                        HostControlView()
                    }
                }
            }

            enum DylibRuntimeLoader {
                @discardableResult
                static func loadDefaultEmbeddedDylib() -> String {
                    let candidates = [
                        Bundle.main.privateFrameworksPath.map { "\\($0)/ModMenu.dylib" },
                        Bundle.main.bundlePath + "/Frameworks/ModMenu.dylib"
                    ].compactMap { $0 }

                    for path in candidates where FileManager.default.fileExists(atPath: path) {
                        if dlopen(path, RTLD_NOW) != nil {
                            return "Loaded \\(URL(fileURLWithPath: path).lastPathComponent)"
                        } else if let err = dlerror() {
                            return "dlopen error: \\(String(cString: err))"
                        }
                    }
                    return "No embedded Frameworks/ModMenu.dylib found (use 3012 Dylib Injector after build)"
                }
            }

            struct HostControlView: View {
                @State private var statusMessage: String = DylibRuntimeLoader.loadDefaultEmbeddedDylib()

                var body: some View {
                    VStack(spacing: 14) {
                        Image(systemName: "wrench.and.screwdriver.fill")
                            .font(.system(size: 46))
                            .foregroundStyle(.orange)
                        Text("\(cleanName) Non-JB Host")
                            .font(.title2.bold())
                        Text(statusMessage)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Retry dlopen") {
                            statusMessage = DylibRuntimeLoader.loadDefaultEmbeddedDylib()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                }
            }
            """
            primaryFile = "Sources/\(cleanName)/\(cleanName)App.swift"
            files = [
                ("Package.swift", packageSwift + "\n"),
                ("xtool.yml", xtoolYML + "\n"),
                ("Info.plist", infoPlist + "\n"),
                (primaryFile, appSwift + "\n"),
                (".github/workflows/build-xtool-ipa.yml", workflowYML)
            ]
        }

        let fm = FileManager.default
        for entry in files {
            let dest = root.appendingPathComponent(entry.relPath)
            try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? entry.content.write(to: dest, atomically: true, encoding: .utf8)
        }
        workspace.reloadTree()

        let primaryURL = root.appendingPathComponent(primaryFile)
        if fm.fileExists(atPath: primaryURL.path) {
            workspace.openFile(at: primaryURL)
            return primaryURL
        }
        return nil
    }

    // MARK: - Sync xtool.yml <-> Package.swift
    @discardableResult
    public func syncXtoolManifests(in workspace: WorkspaceManager, isEnglish: Bool = false) -> String {
        let fm = FileManager.default
        let rootURL = workspace.rootURL.standardizedFileURL
        let packageURL = rootURL.appendingPathComponent("Package.swift")
        let xtoolURL = rootURL.appendingPathComponent("xtool.yml")

        guard fm.fileExists(atPath: packageURL.path),
              let pkgContent = try? String(contentsOf: packageURL, encoding: .utf8) else {
            return isEnglish
                ? "Package.swift not found in project root."
                : "Chưa tìm thấy Package.swift ở thư mục gốc."
        }

        let libraryProducts = Self.extractSwiftPackageLibraryNames(from: pkgContent)
        let packageName = Self.extractSwiftPackageName(from: pkgContent) ?? rootURL.lastPathComponent
        let primaryProduct = libraryProducts.first ?? Self.sanitizeSwiftIdentifier(packageName, fallback: "App3012")
        let cleanBundleID = "com.dev.\(primaryProduct.lowercased())"

        if !fm.fileExists(atPath: xtoolURL.path) {
            var generatedLines = [
                "version: 1",
                "bundleID: \(cleanBundleID)",
                "product: \(primaryProduct)"
            ]
            if fm.fileExists(atPath: rootURL.appendingPathComponent("Info.plist").path) {
                generatedLines.append("infoPath: Info.plist")
            }
            if libraryProducts.count > 1 {
                generatedLines.append("extensions:")
                for extProduct in libraryProducts.dropFirst() {
                    generatedLines.append("  - product: \(extProduct)")
                    generatedLines.append("    infoPath: \(extProduct)-Info.plist")
                }
            }
            let generatedText = generatedLines.joined(separator: "\n") + "\n"
            do {
                try generatedText.write(to: xtoolURL, atomically: true, encoding: .utf8)
                syncOpenTab(in: workspace, fileURL: xtoolURL, content: generatedText)
                workspace.reloadTree()
                return isEnglish
                    ? "Created xtool.yml for product '\(primaryProduct)' (\(libraryProducts.count) library target(s))."
                    : "Đã khởi tạo xtool.yml cho product '\(primaryProduct)' (\(libraryProducts.count) thư viện)."
            } catch {
                return isEnglish
                    ? "Failed to write xtool.yml: \(error.localizedDescription)"
                    : "Không ghi được xtool.yml: \(error.localizedDescription)"
            }
        }

        guard let rawYAML = try? String(contentsOf: xtoolURL, encoding: .utf8) else {
            return isEnglish ? "Failed to read xtool.yml." : "Không đọc được xtool.yml."
        }

        var lines = rawYAML.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var hasVersion = false
        var hasProduct = false
        var hasBundleID = false

        for idx in lines.indices {
            let line = lines[idx]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let isIndented = line.hasPrefix(" ") || line.hasPrefix("\t")
            guard !isIndented else { continue }

            if trimmed.hasPrefix("version:") {
                hasVersion = true
            } else if trimmed.hasPrefix("product:") {
                hasProduct = true
                if !libraryProducts.isEmpty {
                    let current = Self.yamlScalarValue(forKey: "product", in: trimmed) ?? ""
                    if !libraryProducts.contains(current) {
                        lines[idx] = "product: \(primaryProduct)"
                    }
                }
            } else if trimmed.hasPrefix("bundleID:") {
                hasBundleID = true
            }
        }

        if !hasVersion { lines.insert("version: 1", at: 0) }
        if !hasBundleID { lines.append("bundleID: \(cleanBundleID)") }
        if !hasProduct { lines.append("product: \(primaryProduct)") }

        let updatedYAML = lines.joined(separator: "\n").trimmingCharacters(in: .newlines) + "\n"
        do {
            try updatedYAML.write(to: xtoolURL, atomically: true, encoding: .utf8)
            syncOpenTab(in: workspace, fileURL: xtoolURL, content: updatedYAML)
            workspace.reloadTree()
            return isEnglish
                ? "Synced xtool.yml with Package.swift (product: \(primaryProduct))."
                : "Đã đồng bộ xtool.yml với Package.swift (product: \(primaryProduct))."
        } catch {
            return isEnglish
                ? "Failed to update xtool.yml: \(error.localizedDescription)"
                : "Không cập nhật được xtool.yml: \(error.localizedDescription)"
        }
    }

    // MARK: - Build Orchestration (VPS SSH & Offline GitHub Actions)
    public func startBuild(
        workspaceRoot: URL,
        sshService: SSHWorkspaceService,
        runner: CodeRunnerService,
        onWorkspaceChanged: @escaping () -> Void
    ) {
        guard !isBuilding else { return }
        activeTask?.cancel()

        isBuilding = true
        buildLog = "[3012 xtool] Chuẩn bị dự án SwiftPM từ \(workspaceRoot.lastPathComponent)...\n"
        buildStatusText = "Đang chuẩn bị xtool build..."
        runner.consoleOutput = buildLog

        activeTask = Task { [weak self] () -> Void in
            guard let self else { return }
            defer {
                self.isBuilding = false
                self.refreshLocalPackages(in: workspaceRoot)
                onWorkspaceChanged()
            }

            switch self.buildMode {
            case .privateSSHVPS:
                await self.buildViaPrivateSSHVPS(
                    workspaceRoot: workspaceRoot,
                    sshService: sshService,
                    runner: runner,
                    onWorkspaceChanged: onWorkspaceChanged
                )
            case .offlineGitHubActions:
                await self.exportOfflineGitHubPackage(
                    workspaceRoot: workspaceRoot,
                    runner: runner,
                    onWorkspaceChanged: onWorkspaceChanged
                )
            }
        }
    }

    public func cancelBuild() {
        activeTask?.cancel()
        activeTask = nil
        isBuilding = false
        buildStatusText = "Đã huỷ build xtool."
        appendLog("\n[3012 xtool] Người dùng đã huỷ tiến trình build.\n", runner: nil)
    }

    private func buildViaPrivateSSHVPS(
        workspaceRoot: URL,
        sshService: SSHWorkspaceService,
        runner: CodeRunnerService,
        onWorkspaceChanged: @escaping () -> Void
    ) async {
        guard sshService.isConnected else {
            appendLog("[3012 xtool] Chưa kết nối SSH VPS. Hãy đăng nhập VPS trước.\n", runner: runner)
            buildStatusText = "Chưa kết nối SSH VPS"
            return
        }
        guard let zipData = createCleanXtoolZipData(workspaceRoot: workspaceRoot) else {
            appendLog("[3012 xtool] Không thể nén dự án xtool.\n", runner: runner)
            buildStatusText = "Lỗi nén .zip"
            return
        }

        let remoteDir = "/tmp/3012_xtool_\(String(UUID().uuidString.prefix(8)))"
        let b64Zip = zipData.base64EncodedString()
        buildStatusText = "Đang đẩy mã nguồn & chạy xtool trên VPS..."
        appendLog("[3012 xtool] Đang biên dịch qua SSH (\(sshService.connectedProfile?.host ?? "VPS"))...\n", runner: runner)

        let script = """
        rm -rf '\(remoteDir)' && mkdir -p '\(remoteDir)/src' && cd '\(remoteDir)' && \
        cat <<'EOF_ZIP' | base64 -d > proj.zip
        \(b64Zip)
        EOF_ZIP
        unzip -qq -o proj.zip -d src && \
        PROJ=$(find src -maxdepth 4 -type f -name xtool.yml | head -n 1 | xargs -r dirname) && \
        [ -z "$PROJ" ] && PROJ=$(find src -maxdepth 4 -type f -name Package.swift | head -n 1 | xargs -r dirname) ; \
        cd "$PROJ" && \
        if command -v xtool >/dev/null 2>&1; then \
          (xtool dev build --help >/dev/null 2>&1 && xtool dev build 2>&1 || xtool dev 2>&1); \
        else \
          echo "[3012] xtool CLI not installed in PATH — fallback swift build --release" && swift build -c release 2>&1; \
        fi; echo "__3012_EXIT=$?"
        """

        let out = await sshService.executeCommandOnVPS(script)
        appendLog(out + "\n", runner: runner)

        let findOut = await sshService.executeCommandOnVPS(
            "find '\(remoteDir)/src' -type f \\( -name '*.ipa' -o -name '*.dylib' \\) -print"
        )
        let remoteArtifacts = findOut
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix(remoteDir) && ($0.hasSuffix(".ipa") || $0.hasSuffix(".dylib")) }

        if remoteArtifacts.isEmpty {
            _ = await sshService.executeCommandOnVPS("rm -rf '\(remoteDir)'")
            buildStatusText = "Chưa có .ipa đầu ra — kiểm tra log VPS"
            return
        }

        let packagesDir = workspaceRoot.appendingPathComponent("packages", isDirectory: true)
        try? FileManager.default.createDirectory(at: packagesDir, withIntermediateDirectories: true)
        var fetched: [String] = []
        for path in remoteArtifacts {
            let fileName = (path as NSString).lastPathComponent
            let b64Bin = await sshService.executeCommandOnVPS("base64 -w0 '\(path)' 2>/dev/null || base64 '\(path)'")
                .replacingOccurrences(of: "\n", with: "")
                .replacingOccurrences(of: "\r", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let decoded = Data(base64Encoded: b64Bin) {
                try? decoded.write(to: packagesDir.appendingPathComponent(fileName), options: .atomic)
                fetched.append(fileName)
            }
        }
        _ = await sshService.executeCommandOnVPS("rm -rf '\(remoteDir)'")

        if fetched.isEmpty {
            buildStatusText = "Không tải được file kết quả từ VPS"
        } else {
            let summary = fetched.joined(separator: ", ")
            appendLog("[3012 xtool] Đã tải về packages/: \(summary)\n", runner: runner)
            buildStatusText = "Thành công (VPS): \(summary)"
            onWorkspaceChanged()
        }
    }

    private func exportOfflineGitHubPackage(
        workspaceRoot: URL,
        runner: CodeRunnerService,
        onWorkspaceChanged: @escaping () -> Void
    ) async {
        let fm = FileManager.default
        let summary = inspectWorkspace(workspaceRoot)
        let product = summary.productName.isEmpty ? workspaceRoot.lastPathComponent : summary.productName
        let workflowPath = workspaceRoot.appendingPathComponent(".github/workflows/build-xtool-ipa.yml")
        try? fm.createDirectory(at: workflowPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Self.githubWorkflowTemplate(productName: product).write(to: workflowPath, atomically: true, encoding: .utf8)

        guard let zipData = createCleanXtoolZipData(workspaceRoot: workspaceRoot) else {
            appendLog("[3012 xtool] Lỗi đóng gói .zip ngoại tuyến.\n", runner: runner)
            buildStatusText = "Lỗi nén .zip"
            return
        }

        let packagesDir = workspaceRoot.appendingPathComponent("packages", isDirectory: true)
        try? fm.createDirectory(at: packagesDir, withIntermediateDirectories: true)
        let archiveName = "\(workspaceRoot.lastPathComponent)-xtool.zip"
        let outURL = packagesDir.appendingPathComponent(archiveName)
        do {
            try zipData.write(to: outURL, options: .atomic)
            appendLog("[3012 xtool] Đã tạo .github/workflows/build-xtool-ipa.yml và đóng gói tại packages/\(archiveName).\n", runner: runner)
            buildStatusText = "Đã xuất \(archiveName)"
            onWorkspaceChanged()
        } catch {
            appendLog("[3012 xtool] Không ghi được file .zip: \(error.localizedDescription)\n", runner: runner)
            buildStatusText = "Lỗi ghi file"
        }
    }

    // MARK: - On-Device .dylib Injector & Mach-O Patcher (LC_LOAD_DYLIB)
    @discardableResult
    public func injectDylibIntoIPA(
        ipaURL: URL,
        dylibURL: URL,
        workspaceRoot: URL,
        options: XtoolInjectionOptions = XtoolInjectionOptions(),
        runner: CodeRunnerService? = nil
    ) async -> URL? {
        guard !isInjecting else { return nil }
        isInjecting = true
        defer {
            isInjecting = false
            refreshLocalPackages(in: workspaceRoot)
        }

        buildLog += "[3012 Dylib Injector] Bắt đầu nhúng \(dylibURL.lastPathComponent) vào \(ipaURL.lastPathComponent)...\n"
        buildStatusText = "Đang giải nén .ipa..."
        runner?.consoleOutput = buildLog

        do {
            let progressHandler: @Sendable (String) -> Void = { [weak self, weak runner] msg in
                Task { @MainActor in
                    guard let self else { return }
                    self.buildLog += msg + "\n"
                    self.buildStatusText = msg
                    runner?.consoleOutput = self.buildLog
                }
            }
            let outputURL = try await Task.detached(priority: .userInitiated) {
                try Self.performOnDeviceDylibInjection(
                    ipaURL: ipaURL,
                    dylibURL: dylibURL,
                    workspaceRoot: workspaceRoot,
                    options: options,
                    onProgress: progressHandler
                )
            }.value
            buildLog += "[3012 Dylib Injector] Hoàn tất: packages/\(outputURL.lastPathComponent)\n"
            buildStatusText = "Đã nhúng: \(outputURL.lastPathComponent)"
            runner?.consoleOutput = buildLog
            return outputURL
        } catch {
            let errText = error.localizedDescription
            buildLog += "[3012 Dylib Injector] LỖI: \(errText)\n"
            buildStatusText = "Lỗi nhúng .dylib: \(errText)"
            runner?.consoleOutput = buildLog
            return nil
        }
    }

    private nonisolated static func performOnDeviceDylibInjection(
        ipaURL: URL,
        dylibURL: URL,
        workspaceRoot: URL,
        options: XtoolInjectionOptions,
        onProgress: @escaping @Sendable (String) -> Void
    ) throws -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: ipaURL.path) else {
            throw XtoolInjectionError.invalidIPA("Không tìm thấy file .ipa nguồn: \(ipaURL.lastPathComponent)")
        }
        guard fm.fileExists(atPath: dylibURL.path) else {
            throw XtoolInjectionError.dylibNotFound("Không tìm thấy file .dylib: \(dylibURL.lastPathComponent)")
        }

        let workRoot = fm.temporaryDirectory.appendingPathComponent("3012_ipainject_\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: workRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workRoot) }

        try unzipIPAWithFallbackEncodings(from: ipaURL, to: workRoot)

        let payloadDir = workRoot.appendingPathComponent("Payload", isDirectory: true)
        guard let payloadItems = try? fm.contentsOfDirectory(at: payloadDir, includingPropertiesForKeys: nil),
              let appBundleURL = payloadItems.first(where: { $0.pathExtension.lowercased() == "app" }) else {
            throw XtoolInjectionError.invalidIPA("Cấu trúc .ipa không hợp lệ (thiếu Payload/*.app).")
        }

        let plistURL = appBundleURL.appendingPathComponent("Info.plist")
        guard let plistData = try? Data(contentsOf: plistURL),
              var plistDict = try PropertyListSerialization.propertyList(from: plistData, options: .mutableContainersAndLeaves, format: nil) as? [String: Any],
              let execName = plistDict["CFBundleExecutable"] as? String,
              !execName.isEmpty else {
            throw XtoolInjectionError.executableMissing("Không đọc được CFBundleExecutable trong Info.plist.")
        }

        let executableURL = appBundleURL.appendingPathComponent(execName)
        guard fm.fileExists(atPath: executableURL.path) else {
            throw XtoolInjectionError.executableMissing("Thiếu file thực thi chính '\(execName)' trong .app.")
        }

        // Update optional Info.plist overrides (Bundle ID / Display Name)
        var plistModified = false
        let cleanBundle = options.bundleIDOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanBundle.isEmpty {
            plistDict["CFBundleIdentifier"] = cleanBundle
            plistModified = true
        }
        let cleanDisplay = options.displayNameOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanDisplay.isEmpty {
            plistDict["CFBundleDisplayName"] = cleanDisplay
            plistDict["CFBundleName"] = cleanDisplay
            plistModified = true
        }
        if plistModified {
            let encodedPlist = try PropertyListSerialization.data(fromPropertyList: plistDict, format: .binary, options: 0)
            try encodedPlist.write(to: plistURL, options: .atomic)
            onProgress("• Đã cập nhật Info.plist (BundleID / DisplayName)")
        }

        // Copy .dylib into Payload/<App>.app/Frameworks/
        let frameworksDir = appBundleURL.appendingPathComponent("Frameworks", isDirectory: true)
        try fm.createDirectory(at: frameworksDir, withIntermediateDirectories: true)
        let dylibFileName = dylibURL.lastPathComponent
        let destDylibURL = frameworksDir.appendingPathComponent(dylibFileName)
        if fm.fileExists(atPath: destDylibURL.path) {
            try fm.removeItem(at: destDylibURL)
        }
        try fm.copyItem(at: dylibURL, to: destDylibURL)
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destDylibURL.path)

        let loadCommandPath = "@executable_path/Frameworks/\(dylibFileName)"
        onProgress("• Đã sao chép \(dylibFileName) vào Frameworks/")

        // Patch 64-bit Mach-O executable with LC_LOAD_DYLIB
        var binaryData = try Data(contentsOf: executableURL)
        let patchStatus = try patchMachOLoadDylib(data: &binaryData, dylibInstallPath: loadCommandPath)
        switch patchStatus {
        case .inserted(let sliceCount, let path):
            try binaryData.write(to: executableURL, options: .atomic)
            onProgress("• Đã chèn LC_LOAD_DYLIB (\(sliceCount) slice) -> \(path)")
        case .alreadyPresent(let path):
            onProgress("• Binary đã chứa LC_LOAD_DYLIB -> \(path) (đã cập nhật .dylib)")
        }
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

        if options.stripOldCodeSignature {
            let sigDir = appBundleURL.appendingPathComponent("_CodeSignature", isDirectory: true)
            if fm.fileExists(atPath: sigDir.path) {
                try? fm.removeItem(at: sigDir)
                onProgress("• Đã xoá _CodeSignature cũ để sẵn sàng re-sign bằng .p12 / ESign / SideStore")
            }
        }

        let macOSXDir = workRoot.appendingPathComponent("__MACOSX", isDirectory: true)
        if fm.fileExists(atPath: macOSXDir.path) {
            try? fm.removeItem(at: macOSXDir)
        }

        let packagesDir = workspaceRoot.appendingPathComponent("packages", isDirectory: true)
        try fm.createDirectory(at: packagesDir, withIntermediateDirectories: true)
        let baseAppName = ipaURL.deletingPathExtension().lastPathComponent
        let outputURL = packagesDir.appendingPathComponent("\(baseAppName)-Injected.ipa")
        if fm.fileExists(atPath: outputURL.path) {
            try fm.removeItem(at: outputURL)
        }

        onProgress("• Đang đóng gói lại thành \(outputURL.lastPathComponent)...")
        do {
            try fm.zipItem(at: workRoot, to: outputURL, shouldKeepParent: false)
        } catch {
            throw XtoolInjectionError.packagingFailed("Không nén được file .ipa đầu ra: \(error.localizedDescription)")
        }
        return outputURL
    }

    // Pure Swift Mach-O 64-bit / Fat Universal Binary LC_LOAD_DYLIB Patcher
    public nonisolated static func patchMachOLoadDylib(
        data: inout Data,
        dylibInstallPath: String
    ) throws -> XtoolMachOPatchStatus {
        guard data.count >= 32 else {
            throw XtoolInjectionError.invalidMachO("File thực thi quá nhỏ, không phải Mach-O hợp lệ.")
        }

        let magicLE = readUInt32LE(data, at: 0)
        if magicLE == 0xfeedfacf { // MH_MAGIC_64
            let inserted = try patchSingleSlice64(data: &data, sliceOffset: 0, sliceLimit: data.count, dylibInstallPath: dylibInstallPath)
            return inserted ? .inserted(sliceCount: 1, loadPath: dylibInstallPath) : .alreadyPresent(loadPath: dylibInstallPath)
        }

        let magicBE = readUInt32BE(data, at: 0)
        if magicBE == 0xcafebabe { // FAT_MAGIC (Big-Endian header; 0xbebafeca when read LE)
            let archCount = Int(readUInt32BE(data, at: 4))
            guard archCount > 0 && archCount <= 16, data.count >= 8 + archCount * 20 else {
                throw XtoolInjectionError.invalidMachO("Header Fat Binary không hợp lệ.")
            }
            var patchedSlices = 0
            var alreadyHad = false
            for idx in 0..<archCount {
                let archBase = 8 + idx * 20
                let sliceOffset = Int(readUInt32BE(data, at: archBase + 8))
                let sliceSize = Int(readUInt32BE(data, at: archBase + 12))
                guard sliceOffset >= 0, sliceSize >= 32, sliceOffset + sliceSize <= data.count else { continue }
                if readUInt32LE(data, at: sliceOffset) == 0xfeedfacf {
                    let inserted = try patchSingleSlice64(
                        data: &data,
                        sliceOffset: sliceOffset,
                        sliceLimit: sliceOffset + sliceSize,
                        dylibInstallPath: dylibInstallPath
                    )
                    if inserted {
                        patchedSlices += 1
                    } else {
                        alreadyHad = true
                    }
                }
            }
            if patchedSlices > 0 {
                return .inserted(sliceCount: patchedSlices, loadPath: dylibInstallPath)
            }
            if alreadyHad {
                return .alreadyPresent(loadPath: dylibInstallPath)
            }
            throw XtoolInjectionError.invalidMachO("Không tìm thấy slice 64-bit (arm64) trong Fat Binary.")
        }

        throw XtoolInjectionError.invalidMachO("Chỉ hỗ trợ Mach-O 64-bit (arm64 / arm64e).")
    }

    private nonisolated static func patchSingleSlice64(
        data: inout Data,
        sliceOffset: Int,
        sliceLimit: Int,
        dylibInstallPath: String
    ) throws -> Bool {
        let headerSize = 32 // sizeof(mach_header_64)
        guard sliceOffset + headerSize <= sliceLimit else {
            throw XtoolInjectionError.invalidMachO("Mach-O 64-bit header bị cắt cụt.")
        }

        let ncmds = Int(readUInt32LE(data, at: sliceOffset + 16))
        let sizeofcmds = Int(readUInt32LE(data, at: sliceOffset + 20))
        let commandsStart = sliceOffset + headerSize
        let commandsEnd = commandsStart + sizeofcmds
        guard commandsEnd <= sliceLimit else {
            throw XtoolInjectionError.invalidMachO("Vùng Load Commands vượt kích thước slice Mach-O.")
        }

        // Scan existing load commands for duplicate LC_LOAD_DYLIB or first section file offset
        var cursor = commandsStart
        var minSectionOffset = sliceLimit - sliceOffset
        for _ in 0..<ncmds {
            guard cursor + 8 <= commandsEnd else { break }
            let cmd = readUInt32LE(data, at: cursor)
            let cmdSize = Int(readUInt32LE(data, at: cursor + 4))
            guard cmdSize >= 8 && cursor + cmdSize <= commandsEnd else { break }

            // LC_LOAD_DYLIB (0x0c) | LC_LOAD_WEAK_DYLIB (0x80000018) | LC_REEXPORT_DYLIB (0x8000001f)
            if (cmd == 0x0000000c || cmd == 0x80000018 || cmd == 0x8000001f), cmdSize >= 24 {
                let nameOffset = Int(readUInt32LE(data, at: cursor + 8))
                let strStart = cursor + nameOffset
                if strStart >= cursor + 24 && strStart < cursor + cmdSize {
                    let sub = data[strStart..<(cursor + cmdSize)]
                    let existingName = String(bytes: sub.prefix(while: { $0 != 0 }), encoding: .utf8) ?? ""
                    if existingName == dylibInstallPath {
                        return false
                    }
                }
            }

            // LC_SEGMENT_64 (0x19): find earliest non-zero section file offset inside __TEXT
            if cmd == 0x00000019, cmdSize >= 72 {
                let nsects = Int(readUInt32LE(data, at: cursor + 64))
                var sectBase = cursor + 72
                for _ in 0..<nsects {
                    guard sectBase + 80 <= cursor + cmdSize else { break }
                    let sectOffset = Int(readUInt32LE(data, at: sectBase + 48))
                    if sectOffset > 0 && sectOffset < minSectionOffset {
                        minSectionOffset = sectOffset
                    }
                    sectBase += 80
                }
            }

            cursor += cmdSize
        }

        let pathBytes = Array(dylibInstallPath.utf8)
        let unalignedSize = 24 + pathBytes.count + 1
        let newCmdSize = (unalignedSize + 7) & ~7

        let firstCodeFilePos = sliceOffset + minSectionOffset
        let availablePadding = firstCodeFilePos - commandsEnd
        guard availablePadding >= newCmdSize else {
            throw XtoolInjectionError.insufficientHeaderPadding(
                available: max(0, availablePadding),
                required: newCmdSize
            )
        }

        var loadCmd = Data(count: newCmdSize)
        writeUInt32LE(0x0000000c, to: &loadCmd, at: 0)          // LC_LOAD_DYLIB
        writeUInt32LE(UInt32(newCmdSize), to: &loadCmd, at: 4)  // cmdsize (8-byte aligned)
        writeUInt32LE(24, to: &loadCmd, at: 8)                  // dylib.name.offset
        writeUInt32LE(2, to: &loadCmd, at: 12)                  // timestamp
        writeUInt32LE(0x00010000, to: &loadCmd, at: 16)         // current_version 1.0.0
        writeUInt32LE(0x00010000, to: &loadCmd, at: 20)         // compatibility_version 1.0.0
        loadCmd.replaceSubrange(24..<(24 + pathBytes.count), with: pathBytes)

        data.replaceSubrange(commandsEnd..<(commandsEnd + newCmdSize), with: loadCmd)
        writeUInt32LE(UInt32(ncmds + 1), to: &data, at: sliceOffset + 16)
        writeUInt32LE(UInt32(sizeofcmds + newCmdSize), to: &data, at: sliceOffset + 20)
        return true
    }

    private nonisolated static func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
        let b0 = UInt32(data[offset])
        let b1 = UInt32(data[offset + 1]) << 8
        let b2 = UInt32(data[offset + 2]) << 16
        let b3 = UInt32(data[offset + 3]) << 24
        return b0 | b1 | b2 | b3
    }

    private nonisolated static func readUInt32BE(_ data: Data, at offset: Int) -> UInt32 {
        let b0 = UInt32(data[offset]) << 24
        let b1 = UInt32(data[offset + 1]) << 16
        let b2 = UInt32(data[offset + 2]) << 8
        let b3 = UInt32(data[offset + 3])
        return b0 | b1 | b2 | b3
    }

    private nonisolated static func writeUInt32LE(_ value: UInt32, to data: inout Data, at offset: Int) {
        data[offset] = UInt8(value & 0xff)
        data[offset + 1] = UInt8((value >> 8) & 0xff)
        data[offset + 2] = UInt8((value >> 16) & 0xff)
        data[offset + 3] = UInt8((value >> 24) & 0xff)
    }

    private nonisolated static func unzipIPAWithFallbackEncodings(from archiveURL: URL, to destinationURL: URL) throws {
        let fm = FileManager.default
        do {
            try fm.unzipItem(at: archiveURL, to: destinationURL, skipCRC32: false, pathEncoding: .utf8)
        } catch {
            if let items = try? fm.contentsOfDirectory(at: destinationURL, includingPropertiesForKeys: nil) {
                for item in items { try? fm.removeItem(at: item) }
            }
            do {
                try fm.unzipItem(at: archiveURL, to: destinationURL, skipCRC32: false, pathEncoding: .isoLatin1)
            } catch {
                if let items = try? fm.contentsOfDirectory(at: destinationURL, includingPropertiesForKeys: nil) {
                    for item in items { try? fm.removeItem(at: item) }
                }
                try fm.unzipItem(at: archiveURL, to: destinationURL)
            }
        }
    }

    // MARK: - Helpers & Templates
    private func appendLog(_ text: String, runner: CodeRunnerService?) {
        buildLog += text
        if buildLog.count > 120_000 {
            buildLog = String(buildLog.suffix(100_000))
        }
        runner?.consoleOutput = buildLog
    }

    private func syncOpenTab(in workspace: WorkspaceManager, fileURL: URL, content: String) {
        if let tabIdx = workspace.openTabs.firstIndex(where: { $0.fileURL.standardizedFileURL == fileURL.standardizedFileURL }) {
            workspace.openTabs[tabIdx].content = content
            workspace.openTabs[tabIdx].savedContent = content
        }
    }

    private func createCleanXtoolZipData(workspaceRoot: URL) -> Data? {
        let fm = FileManager.default
        let stageID = UUID().uuidString
        let stageParent = fm.temporaryDirectory.appendingPathComponent("3012_xstage_\(stageID)", isDirectory: true)
        let projectStage = stageParent.appendingPathComponent(workspaceRoot.lastPathComponent, isDirectory: true)
        let destZip = fm.temporaryDirectory.appendingPathComponent("3012_xtool_\(stageID).zip")

        defer {
            try? fm.removeItem(at: stageParent)
            try? fm.removeItem(at: destZip)
        }

        do {
            try fm.createDirectory(at: projectStage, withIntermediateDirectories: true)
            let excludedDirs: Set<String> = [".git", ".build", ".swiftpm", "packages", "xtool", ".xtool-tmp", "node_modules", "__MACOSX"]
            if let enumerator = fm.enumerator(
                at: workspaceRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            ) {
                let rootPath = workspaceRoot.standardizedFileURL.path
                for case let url as URL in enumerator {
                    let name = url.lastPathComponent
                    if excludedDirs.contains(name) || name.hasPrefix(".3012") || name == ".DS_Store" {
                        enumerator.skipDescendants()
                        continue
                    }
                    let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    var rel = url.standardizedFileURL.path
                    if rel.hasPrefix(rootPath) {
                        rel = String(rel.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    }
                    guard !rel.isEmpty else { continue }
                    let targetURL = projectStage.appendingPathComponent(rel)
                    if isDir {
                        try fm.createDirectory(at: targetURL, withIntermediateDirectories: true)
                    } else {
                        try fm.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try fm.copyItem(at: url, to: targetURL)
                    }
                }
            }

            try fm.zipItem(at: projectStage, to: destZip, shouldKeepParent: true)
            return try Data(contentsOf: destZip)
        } catch {
            return nil
        }
    }

    private static func yamlScalarValue(forKey key: String, in trimmedLine: String) -> String? {
        guard trimmedLine.hasPrefix("\(key):") else { return nil }
        var val = String(trimmedLine.dropFirst(key.count + 1))
        if let hashRange = val.range(of: " #") {
            val = String(val[..<hashRange.lowerBound])
        }
        return val
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    private static func extractSwiftPackageName(from packageSwift: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"name\s*:\s*"([^"]+)""#),
              let match = regex.firstMatch(in: packageSwift, range: NSRange(location: 0, length: (packageSwift as NSString).length)),
              match.numberOfRanges >= 2 else { return nil }
        return (packageSwift as NSString).substring(with: match.range(at: 1))
    }

    private static func extractSwiftPackageLibraryNames(from packageSwift: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\.library\s*\(\s*name\s*:\s*"([^"]+)""#) else {
            return []
        }
        let ns = packageSwift as NSString
        return regex.matches(in: packageSwift, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            guard m.numberOfRanges >= 2 else { return nil }
            return ns.substring(with: m.range(at: 1))
        }
    }

    public static func sanitizeSwiftIdentifier(_ raw: String, fallback: String) -> String {
        let allowed = raw.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0 == "_"
        }
        var out = String(String.UnicodeScalarView(allowed))
        if let first = out.first, first.isNumber {
            out = "X" + out
        }
        return out.isEmpty ? fallback : out
    }

    private static func standardAppInfoPlist(displayName: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>CFBundleDisplayName</key>
        \t<string>\(displayName)</string>
        \t<key>UILaunchScreen</key>
        \t<dict/>
        </dict>
        </plist>
        """
    }

    private static func widgetExtensionInfoPlist(extensionName: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>CFBundleDisplayName</key>
        \t<string>\(extensionName)</string>
        \t<key>NSExtension</key>
        \t<dict>
        \t\t<key>NSExtensionPointIdentifier</key>
        \t\t<string>com.apple.widgetkit-extension</string>
        \t</dict>
        </plist>
        """
    }

    private static func githubWorkflowTemplate(productName: String) -> String {
        """
        name: Build xtool Unsigned IPA

        on:
          workflow_dispatch:
          push:

        jobs:
          build-xtool:
            runs-on: macos-14
            steps:
              - uses: actions/checkout@v4
              - name: Package SwiftPM via xtool
                run: |
                  brew install xtool-org/tap/xtool || true
                  if command -v xtool >/dev/null 2>&1; then
                    xtool dev build || xtool dev --help
                  else
                    swift build -c release
                  fi
              - uses: actions/upload-artifact@v4
                if: always()
                with:
                  name: \(productName)-xtool-output
                  path: |
                    xtool/**/*.ipa
                    *.ipa
                    .build/release/**
        """
    }
}
