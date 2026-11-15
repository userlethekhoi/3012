import Foundation
import SwiftUI
import CryptoKit
import ZIPFoundation

public enum TheosBuildMode: String, CaseIterable, Identifiable, Codable {
    case directVPSTerminal = "directVPSTerminal"
    case communityServer = "communityServer"
    case privateSSHVPS = "privateSSHVPS"
    case offlineExport = "offlineExport"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .directVPSTerminal: return L10n.tr("Terminal Linux VPS Trực Tiếp (Không Gửi Lại Zip)", "Direct Linux VPS Terminal (Live Make / Zero Zip)")
        case .communityServer: return L10n.tr("Máy chủ Cộng đồng (Không cần JB / VPS)", "Community Build Server (No JB / VPS Needed)")
        case .privateSSHVPS: return L10n.tr("VPS SSH Nền (Đồng Bộ Delta & Kéo .deb)", "Private SSH VPS (Delta Sync & Auto Pull)")
        case .offlineExport: return L10n.tr("Ngoại tuyến (.zip + GitHub Actions)", "Offline Export (.zip + GitHub Actions)")
        }
    }

    public var subtitle: String {
        switch self {
        case .directVPSTerminal: return L10n.tr("Chạy make trực tiếp trong Terminal SSH VPS; giữ cache .theos hoặc sửa trực tiếp file trên VPS", "Runs make directly in live VPS SSH Terminal; keeps .theos cache or edits remote files live")
        case .communityServer: return L10n.tr("Biên dịch cách ly trong container Docker (--network none, không lưu code)", "Isolated Docker sandbox (--network none, ephemeral RAM build)")
        case .privateSSHVPS: return L10n.tr("Chỉ tải file thay đổi qua SSH (SHA-256), giữ cache .theos và tự tải .deb về máy", "Uploads only changed files over SSH, keeps .theos cache and fetches .deb/.dylib")
        case .offlineExport: return L10n.tr("Tạo sẵn GitHub Actions workflow & đóng gói .zip sạch để tự build", "Generates GitHub Actions workflow & clean .zip archive")
        }
    }
}

public enum TheosPackageScheme: String, CaseIterable, Identifiable, Codable {
    case rootless = "rootless"
    case roothide = "roothide"
    case rootful = "rootful"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .rootless: return L10n.tr("Rootless (/var/jb — iOS 15+ Dopamine/Palera1n)", "Rootless (/var/jb — iOS 15+ Dopamine/Palera1n)")
        case .roothide: return L10n.tr("RootHide (Ẩn Jailbreak)", "RootHide (Hide Jailbreak)")
        case .rootful: return L10n.tr("Rootful (iOS 14 trở xuống)", "Rootful (Legacy iOS 14 & below)")
        }
    }
}

public enum TheosTemplateKind: String, CaseIterable, Identifiable {
    case standardTweak = "standardTweak"
    case modMenuDylib = "modMenuDylib"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .standardTweak: return L10n.tr("Logos Tweak (.x -> .deb / .dylib)", "Logos Tweak (.x -> .deb / .dylib)")
        case .modMenuDylib: return L10n.tr("Floating Mod Menu HUD (.xm + Objective-C++ UI -> .dylib / .deb)", "Floating Mod Menu HUD (.xm + Objective-C++ UI -> .dylib / .deb)")
        }
    }

    public var summary: String {
        switch self {
        case .standardTweak:
            return L10n.tr(
                "Makefile + Tweak.x + control + plist chuẩn Theos. Phù hợp tweak hệ thống hoặc app.",
                "Standard Theos Makefile + Tweak.x + control + plist. Ideal for system or app tweaks."
            )
        case .modMenuDylib:
            return L10n.tr(
                "Kèm cửa sổ HUD nổi kéo thả được (MenuOverlayView.h/.mm) với công tắc lưu trạng thái.",
                "Includes draggable floating HUD window (MenuOverlayView.h/.mm) with persistent toggles."
            )
        }
    }
}

public struct TheosArtifactItem: Identifiable, Equatable {
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

private struct TheosBuildJobResponse: Decodable {
    struct FileEntry: Decodable {
        let name: String
        let size: Int64
    }

    let id: String
    let state: String
    let position: Int?
    let log: String?
    let logOffset: Int?
    let logTruncated: Bool?
    let exitCode: Int?
    let error: String?
    let files: [FileEntry]?
    let elapsed: Double?
}

private struct TheosServerErrorResponse: Decodable {
    let error: String?
    let message: String?
}

private struct TheosHealthResponse: Decodable {
    struct Limits: Decodable {
        let maxUploadMB: Int?
        let timeoutSec: Int?
        let perDeviceHour: Int?
    }

    let ok: Bool
    let version: String?
    let queued: Int?
    let running: Int?
    let capacity: Int?
    let limits: Limits?
}

@MainActor
public final class TheosBuildService: ObservableObject {
    public static let defaultServerURL = "https://build.kaydus.xyz"

    @Published public var buildMode: TheosBuildMode {
        didSet { UserDefaults.standard.set(buildMode.rawValue, forKey: "3012.theos.buildMode") }
    }
    @Published public var packageScheme: TheosPackageScheme {
        didSet { UserDefaults.standard.set(packageScheme.rawValue, forKey: "3012.theos.packageScheme") }
    }
    @Published public var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: "3012.theos.serverURL") }
    }
    @Published public var hasAcceptedPrivacyConsent: Bool {
        didSet { UserDefaults.standard.set(hasAcceptedPrivacyConsent, forKey: "3012.theos.privacyConsent") }
    }

    @Published public private(set) var isBuilding: Bool = false
    @Published public private(set) var buildStatusText: String = "Sẵn sàng build .deb / .dylib"
    @Published public var buildLog: String = ""
    @Published public private(set) var downloadedArtifacts: [TheosArtifactItem] = []
    @Published public private(set) var serverHealthSummary: String? = nil
    @Published public private(set) var lastRemoteBuildDir: String? = nil

    public var onOpenTerminalForLiveMake: (() -> Void)?
    public var onBeforeRemoteMake: (() -> Void)?

    private var activeTask: Task<Void, Never>?
    private var buildGeneration: Int = 0
    private var activeJobID: String?
    private var activeBuildBaseURL: URL?
    private let deviceID: String
    nonisolated private static let maxCommunityUploadBytes = 20 * 1024 * 1024

    public init() {
        if let rawMode = UserDefaults.standard.string(forKey: "3012.theos.buildMode"),
           let mode = TheosBuildMode(rawValue: rawMode) {
            self.buildMode = mode
        } else {
            self.buildMode = .communityServer
        }

        if let rawScheme = UserDefaults.standard.string(forKey: "3012.theos.packageScheme"),
           let scheme = TheosPackageScheme(rawValue: rawScheme) {
            self.packageScheme = scheme
        } else {
            self.packageScheme = .rootless
        }

        let storedURL = UserDefaults.standard.string(forKey: "3012.theos.serverURL")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if storedURL.isEmpty || Self.isMisconfiguredRootHost(storedURL) {
            self.serverURL = Self.defaultServerURL
            UserDefaults.standard.set(Self.defaultServerURL, forKey: "3012.theos.serverURL")
        } else {
            self.serverURL = storedURL
        }
        self.hasAcceptedPrivacyConsent = UserDefaults.standard.bool(forKey: "3012.theos.privacyConsent")

        if let existingID = KeychainVault.loadString(forKey: "theos.device.id"),
           existingID.count >= 8 {
            self.deviceID = existingID
        } else {
            let freshID = UUID().uuidString
            KeychainVault.saveString(freshID, forKey: "theos.device.id")
            self.deviceID = freshID
        }
    }

    // MARK: - Workspace Detection
    public func isTheosWorkspace(_ rootURL: URL) -> Bool {
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(atPath: rootURL.path)) ?? []
        let makefileName = entries.first {
            let lower = $0.lowercased()
            return lower == "makefile" || lower == "gnumakefile"
        }
        let hasControl = entries.contains { $0.lowercased() == "control" }
        if makefileName != nil && hasControl {
            return true
        }
        if let makefileName {
            let mfURL = rootURL.appendingPathComponent(makefileName)
            if let makefileText = try? String(contentsOf: mfURL, encoding: .utf8) {
                let markers = ["THEOS", "tweak.mk", "application.mk", "tool.mk", "TWEAK_NAME"]
                if markers.contains(where: { makefileText.contains($0) }) {
                    return true
                }
            }
        }
        return entries.contains { name in
            let lower = name.lowercased()
            return lower.hasSuffix(".x") || lower.hasSuffix(".xm") || lower.hasSuffix(".xi") || lower.hasSuffix(".xmi")
        }
    }

    public func resolveTheosProjectRoot(activeFileURL: URL?, workspaceRoot: URL) -> URL? {
        let fm = FileManager.default
        let rootStd = workspaceRoot.standardizedFileURL
        let rootCanon = WorkspaceManager.canonicalPath(rootStd)
        let rootPrefix = rootCanon == "/" ? "/" : rootCanon + "/"

        var ancestorDirs: [URL] = []
        if let activeFileURL {
            var currentDir = activeFileURL.deletingLastPathComponent().standardizedFileURL
            for _ in 0..<12 {
                let currentCanon = WorkspaceManager.canonicalPath(currentDir)
                guard currentCanon == rootCanon || currentCanon.hasPrefix(rootPrefix) else { break }
                ancestorDirs.append(currentDir)
                if currentCanon == rootCanon { break }
                let parent = currentDir.deletingLastPathComponent().standardizedFileURL
                if WorkspaceManager.canonicalPath(parent) == currentCanon { break }
                currentDir = parent
            }
        }

        // First prefer an ancestor that explicitly holds a Makefile/GNUmakefile + Theos structure
        for dir in ancestorDirs {
            let entries = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
            let hasMakefile = entries.contains {
                let lower = $0.lowercased()
                return lower == "makefile" || lower == "gnumakefile"
            }
            if hasMakefile && isTheosWorkspace(dir) {
                return dir
            }
        }

        if isTheosWorkspace(rootStd) {
            return rootStd
        }
        for dir in ancestorDirs where isTheosWorkspace(dir) {
            return dir
        }
        return nil
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

        let valid = urls.compactMap { url -> TheosArtifactItem? in
            let lower = url.lastPathComponent.lowercased()
            guard lower.hasSuffix(".deb") || lower.hasSuffix(".dylib") || lower.hasSuffix(".zip") else {
                return nil
            }
            let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            return TheosArtifactItem(name: url.lastPathComponent, size: size, localURL: url)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        downloadedArtifacts = valid
    }

    // MARK: - 1-Tap Project Templates
    @discardableResult
    public func scaffoldTemplate(
        kind: TheosTemplateKind,
        tweakName rawName: String,
        packageID rawBundleID: String,
        bundleFilter rawFilter: String,
        in workspace: WorkspaceManager
    ) -> URL? {
        let cleanName = Self.sanitizeSymbolName(rawName, fallback: kind == .modMenuDylib ? "ModMenu3012" : "MyTweak3012")
        let rawPkg = rawBundleID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let validPkgScalars = rawPkg.unicodeScalars.filter {
            ($0.value >= 97 && $0.value <= 122) || ($0.value >= 48 && $0.value <= 57) || $0 == "." || $0 == "-"
        }
        let trimmedPkg = String(String.UnicodeScalarView(validPkgScalars)).trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
        let fallbackPkgSlug = cleanName.lowercased().replacingOccurrences(of: "_", with: "-")
        let cleanPkgID = trimmedPkg.isEmpty ? "com.dev.\(fallbackPkgSlug)" : trimmedPkg
        let cleanFilter = rawFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "com.apple.springboard"
            : rawFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        let escapedFilter = Self.escapeXML(cleanFilter)

        let root = workspace.rootURL
        let files: [(relPath: String, content: String)]

        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>Filter</key>
        \t<dict>
        \t\t<key>Bundles</key>
        \t\t<array>
        \t\t\t<string>\(escapedFilter)</string>
        \t\t</array>
        \t</dict>
        </dict>
        </plist>
        """

        let controlContent = """
        Package: \(cleanPkgID)
        Name: \(cleanName)
        Version: 1.0.0
        Architecture: iphoneos-arm
        Description: Built with 3012 Mobile IDE
        Maintainer: 3012 Developer
        Author: 3012 Developer
        Section: Tweaks
        Depends: mobilesubstrate (>= 0.9.5000)
        """

        let workflowYML = Self.githubWorkflowTemplate(scheme: packageScheme)

        switch kind {
        case .standardTweak:
            let makefile = """
            TARGET := iphone:clang:latest:14.0
            INSTALL_TARGET_PROCESSES = SpringBoard
            ARCHS = arm64 arm64e

            include $(THEOS)/makefiles/common.mk

            TWEAK_NAME = \(cleanName)

            \(cleanName)_FILES = Tweak.x
            \(cleanName)_CFLAGS = -fobjc-arc

            include $(THEOS_MAKE_PATH)/tweak.mk
            """

            let tweakX = """
            #import <UIKit/UIKit.h>

            %hook SpringBoard

            - (void)applicationDidFinishLaunching:(id)application {
                %orig;
                NSLog(@"[\(cleanName)] Tweak loaded via 3012 Mobile IDE!");
            }

            %end
            """

            files = [
                ("Makefile", makefile),
                ("control", controlContent + "\n"),
                ("\(cleanName).plist", plistContent + "\n"),
                ("Tweak.x", tweakX + "\n"),
                (".github/workflows/theos-build.yml", workflowYML)
            ]

        case .modMenuDylib:
            let makefile = """
            export _LOGOS_DEFAULT_GENERATOR = internal
            TARGET := iphone:clang:latest:14.0
            ARCHS = arm64 arm64e

            include $(THEOS)/makefiles/common.mk

            TWEAK_NAME = \(cleanName)

            \(cleanName)_FILES = Tweak.xm MenuOverlayView.mm
            \(cleanName)_FRAMEWORKS = UIKit QuartzCore CoreGraphics
            \(cleanName)_CFLAGS = -fobjc-arc -Wno-deprecated-declarations

            include $(THEOS_MAKE_PATH)/tweak.mk
            """

            let overlayHeader = """
            #import <UIKit/UIKit.h>

            NS_ASSUME_NONNULL_BEGIN

            @interface MenuOverlayView : UIView
            + (instancetype)sharedMenu;
            - (void)installOnKeyWindow;
            - (BOOL)isFeatureEnabledForKey:(NSString *)key;
            @end

            NS_ASSUME_NONNULL_END
            """

            let overlayImpl = """
            #import "MenuOverlayView.h"
            #import <QuartzCore/QuartzCore.h>

            @interface MenuOverlayView ()
            @property (nonatomic, strong) UIButton *floatingToggleButton;
            @property (nonatomic, strong) UIView *panelView;
            @property (nonatomic, assign) BOOL isMenuExpanded;
            @end

            @implementation MenuOverlayView

            + (instancetype)sharedMenu {
                static MenuOverlayView *instance = nil;
                static dispatch_once_t onceToken;
                dispatch_once(&onceToken, ^{
                    instance = [[MenuOverlayView alloc] initWithFrame:CGRectMake(20, 96, 252, 224)];
                });
                return instance;
            }

            - (instancetype)initWithFrame:(CGRect)frame {
                self = [super initWithFrame:frame];
                if (self) {
                    self.backgroundColor = [UIColor clearColor];
                    self.layer.zPosition = 99999.0;
                    [self buildHUD];
                }
                return self;
            }

            - (void)buildHUD {
                self.floatingToggleButton = [UIButton buttonWithType:UIButtonTypeSystem];
                self.floatingToggleButton.frame = CGRectMake(0, 0, 46, 46);
                self.floatingToggleButton.backgroundColor = [UIColor colorWithRed:0.08 green:0.10 blue:0.14 alpha:0.94];
                [self.floatingToggleButton setTitle:@"3012" forState:UIControlStateNormal];
                [self.floatingToggleButton setTitleColor:[UIColor colorWithRed:0.06 green:0.72 blue:0.51 alpha:1.0] forState:UIControlStateNormal];
                self.floatingToggleButton.titleLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightBold];
                self.floatingToggleButton.layer.cornerRadius = 12.0;
                self.floatingToggleButton.layer.borderWidth = 1.2;
                self.floatingToggleButton.layer.borderColor = [UIColor colorWithRed:0.06 green:0.72 blue:0.51 alpha:0.85].CGColor;
                [self.floatingToggleButton addTarget:self action:@selector(toggleMenuVisibility) forControlEvents:UIControlEventTouchUpInside];

                UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleDrag:)];
                [self addGestureRecognizer:pan];
                [self addSubview:self.floatingToggleButton];

                self.panelView = [[UIView alloc] initWithFrame:CGRectMake(0, 52, 248, 168)];
                self.panelView.backgroundColor = [UIColor colorWithRed:0.06 green:0.08 blue:0.11 alpha:0.95];
                self.panelView.layer.cornerRadius = 12.0;
                self.panelView.layer.borderWidth = 1.0;
                self.panelView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.14].CGColor;
                self.panelView.hidden = YES;

                UILabel *header = [[UILabel alloc] initWithFrame:CGRectMake(12, 10, 224, 20)];
                header.text = @"\(cleanName) — Mod Menu";
                header.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightBold];
                header.textColor = [UIColor whiteColor];
                [self.panelView addSubview:header];

                [self addToggleRowAtY:44 title:@"God Mode / Feature 1" prefKey:@"mod_feature_1"];
                [self addToggleRowAtY:86 title:@"Speed Multiplier x2" prefKey:@"mod_feature_2"];
                [self addToggleRowAtY:128 title:@"No Cooldown" prefKey:@"mod_feature_3"];

                [self addSubview:self.panelView];
                self.isMenuExpanded = NO;
            }

            - (void)addToggleRowAtY:(CGFloat)y title:(NSString *)title prefKey:(NSString *)prefKey {
                UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(12, y, 162, 30)];
                label.text = title;
                label.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
                label.textColor = [UIColor colorWithWhite:0.92 alpha:1.0];
                [self.panelView addSubview:label];

                UISwitch *toggle = [[UISwitch alloc] init];
                toggle.center = CGPointMake(214, y + 15);
                toggle.transform = CGAffineTransformMakeScale(0.78, 0.78);
                toggle.onTintColor = [UIColor colorWithRed:0.06 green:0.72 blue:0.51 alpha:1.0];
                toggle.on = [[NSUserDefaults standardUserDefaults] boolForKey:prefKey];
                toggle.accessibilityIdentifier = prefKey;
                [toggle addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
                [self.panelView addSubview:toggle];
            }

            - (void)switchChanged:(UISwitch *)sender {
                NSString *key = sender.accessibilityIdentifier;
                if (key.length > 0) {
                    [[NSUserDefaults standardUserDefaults] setBool:sender.isOn forKey:key];
                }
            }

            - (void)toggleMenuVisibility {
                self.isMenuExpanded = !self.isMenuExpanded;
                self.panelView.hidden = !self.isMenuExpanded;
            }

            - (void)handleDrag:(UIPanGestureRecognizer *)pan {
                if (!self.superview) return;
                CGPoint delta = [pan translationInView:self.superview];
                self.center = CGPointMake(self.center.x + delta.x, self.center.y + delta.y);
                [pan setTranslation:CGPointZero inView:self.superview];
            }

            - (BOOL)isFeatureEnabledForKey:(NSString *)key {
                return [[NSUserDefaults standardUserDefaults] boolForKey:key];
            }

            - (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
                if (self.panelView.hidden) {
                    CGPoint pt = [self convertPoint:point toView:self.floatingToggleButton];
                    if ([self.floatingToggleButton pointInside:pt withEvent:event]) {
                        return self.floatingToggleButton;
                    }
                    return nil;
                }
                return [super hitTest:point withEvent:event];
            }

            - (void)installOnKeyWindow {
                dispatch_async(dispatch_get_main_queue(), ^{
                    UIWindow *targetWindow = nil;
                    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
                        UIWindowScene *ws = (UIWindowScene *)scene;
                        for (UIWindow *win in ws.windows) {
                            if (win.isKeyWindow) {
                                targetWindow = win;
                                break;
                            }
                        }
                        if (targetWindow) break;
                    }
                    if (!targetWindow) {
                        targetWindow = [UIApplication sharedApplication].windows.firstObject;
                    }
                    if (targetWindow && self.superview != targetWindow) {
                        [targetWindow addSubview:self];
                    }
                });
            }

            @end
            """

            let tweakXM = """
            #import <UIKit/UIKit.h>
            #import "MenuOverlayView.h"

            %hook UIWindow

            - (void)makeKeyAndVisible {
                %orig;
                [[MenuOverlayView sharedMenu] installOnKeyWindow];
            }

            %end

            %ctor {
                [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                                  object:nil
                                                                   queue:[NSOperationQueue mainQueue]
                                                              usingBlock:^(NSNotification * _Nonnull note) {
                    [[MenuOverlayView sharedMenu] installOnKeyWindow];
                }];
            }
            """

            files = [
                ("Makefile", makefile),
                ("control", controlContent + "\n"),
                ("\(cleanName).plist", plistContent + "\n"),
                ("MenuOverlayView.h", overlayHeader + "\n"),
                ("MenuOverlayView.mm", overlayImpl + "\n"),
                ("Tweak.xm", tweakXM + "\n"),
                (".github/workflows/theos-build.yml", workflowYML)
            ]
        }

        let fm = FileManager.default
        for entry in files {
            let dest = root.appendingPathComponent(entry.relPath)
            try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            do {
                try entry.content.write(to: dest, atomically: true, encoding: .utf8)
                let stdDest = dest.standardizedFileURL
                if let tabIdx = workspace.openTabs.firstIndex(where: { $0.fileURL.standardizedFileURL == stdDest }) {
                    workspace.openTabs[tabIdx].content = entry.content
                    workspace.openTabs[tabIdx].savedContent = entry.content
                }
                if !workspace.suppressOutboundSyncEvents {
                    workspace.onWorkspaceMutation?(.upsertFile(relativePath: entry.relPath, content: entry.content))
                }
            } catch {
                buildStatusText = "Không ghi được \(entry.relPath): \(error.localizedDescription)"
            }
        }
        workspace.reloadTree()
        workspace.onFileSavedOrChanged?()

        let primaryName = kind == .modMenuDylib ? "Tweak.xm" : "Tweak.x"
        let primaryURL = root.appendingPathComponent(primaryName)
        if fm.fileExists(atPath: primaryURL.path) {
            workspace.openFile(at: primaryURL)
            return primaryURL
        }
        return nil
    }

    // MARK: - Server Health Check
    public func checkServerHealth() async {
        guard let primaryBase = normalizedBaseURL() else {
            serverHealthSummary = "URL máy chủ không hợp lệ."
            return
        }
        do {
            let result = try await performTheosRequest(
                primaryBaseURL: primaryBase,
                escapedPath: "v1/health",
                method: "GET",
                requestTimeout: 12,
                resourceTimeout: 30,
                maxAttempts: 3
            )
            let code = result.response.statusCode
            guard (200...299).contains(code),
                  let health = try? JSONDecoder().decode(TheosHealthResponse.self, from: result.data),
                  health.ok else {
                serverHealthSummary = "Máy chủ phản hồi lỗi HTTP \(code)."
                return
            }
            let running = health.running ?? 0
            let capacity = health.capacity ?? 2
            let queued = health.queued ?? 0
            let ver = health.version ?? "1.0"
            let hostNote = (result.usedBaseURL.host == primaryBase.host) ? "" : " • \(result.usedBaseURL.host ?? "")"
            serverHealthSummary = "Online v\(ver) — Đang chạy \(running)/\(capacity) • Hàng đợi: \(queued)\(hostNote)"
        } catch {
            serverHealthSummary = "Không kết nối được: \(error.localizedDescription)"
        }
    }

    // MARK: - Build Orchestration
    public func startBuild(
        workspaceRoot: URL,
        sshService: SSHWorkspaceService,
        runner: CodeRunnerService,
        workspace: WorkspaceManager? = nil,
        onWorkspaceChanged: @escaping () -> Void
    ) {
        guard !isBuilding else { return }
        activeTask?.cancel()
        buildGeneration &+= 1
        let gen = buildGeneration

        isBuilding = true
        activeBuildBaseURL = nil
        buildLog = "[3012 Theos] Chuẩn bị đóng gói dự án từ \(workspaceRoot.lastPathComponent)...\n"
        buildStatusText = "Đang chuẩn bị biên dịch..."
        runner.consoleOutput = buildLog

        activeTask = Task { [weak self] () -> Void in
            guard let self else { return }
            defer {
                if self.buildGeneration == gen {
                    self.isBuilding = false
                    self.activeJobID = nil
                    self.activeBuildBaseURL = nil
                    self.refreshLocalPackages(in: workspaceRoot)
                    onWorkspaceChanged()
                }
            }

            switch self.buildMode {
            case .directVPSTerminal:
                await self.buildViaDirectVPSTerminal(
                    workspaceRoot: workspaceRoot,
                    sshService: sshService,
                    runner: runner,
                    workspace: workspace,
                    onWorkspaceChanged: onWorkspaceChanged
                )
            case .communityServer:
                await self.buildViaCommunityServer(
                    workspaceRoot: workspaceRoot,
                    runner: runner,
                    onWorkspaceChanged: onWorkspaceChanged
                )
            case .privateSSHVPS:
                await self.buildViaPrivateSSHVPS(
                    workspaceRoot: workspaceRoot,
                    sshService: sshService,
                    runner: runner,
                    workspace: workspace,
                    onWorkspaceChanged: onWorkspaceChanged
                )
            case .offlineExport:
                await self.exportOfflineGitHubPackage(
                    workspaceRoot: workspaceRoot,
                    runner: runner,
                    onWorkspaceChanged: onWorkspaceChanged
                )
            }
        }
    }

    public func cancelBuild() {
        let jobToCancel = activeJobID
        let cancelBase = activeBuildBaseURL ?? normalizedBaseURL()
        activeTask?.cancel()
        activeTask = nil
        activeBuildBaseURL = nil
        isBuilding = false
        buildStatusText = "Đã huỷ build."
        appendLog("\n[3012] Người dùng đã huỷ tiến trình build.\n", runner: nil)

        if let jobID = jobToCancel, let base = cancelBase {
            let deleteURL = base.appendingPathComponent("v1/builds/\(jobID)")
            let dev = deviceID
            Task.detached {
                let session = Self.makeEphemeralTheosSession(requestTimeout: 10, resourceTimeout: 15)
                defer { session.finishTasksAndInvalidate() }
                var req = URLRequest(url: deleteURL)
                req.httpMethod = "DELETE"
                req.timeoutInterval = 10
                req.assumesHTTP3Capable = false
                req.setValue(dev, forHTTPHeaderField: "X-Device-ID")
                req.setValue("close", forHTTPHeaderField: "Connection")
                _ = try? await session.data(for: req)
            }
        }
    }

    // MARK: - Mode 1: Community Remote Build Server (build.kaydus.xyz)
    private func buildViaCommunityServer(
        workspaceRoot: URL,
        runner: CodeRunnerService,
        onWorkspaceChanged: @escaping () -> Void
    ) async {
        guard isTheosWorkspace(workspaceRoot) else {
            let msg = "[3012] Chưa tìm thấy Makefile / control của Theos trong thư mục dự án. Hãy bấm 'Tạo Mẫu Tweak / Mod Menu' trước.\n"
            appendLog(msg, runner: runner)
            buildStatusText = "Thiếu Makefile Theos"
            return
        }
        guard let primaryBase = normalizedBaseURL() else {
            appendLog("[3012] URL Build Server không hợp lệ.\n", runner: runner)
            buildStatusText = "Sai URL máy chủ"
            return
        }

        guard let zipData = await Task.detached(priority: .userInitiated, operation: { () -> Data? in
            Self.createCleanTheosZipData(workspaceRoot: workspaceRoot)
        }).value else {
            appendLog("[3012] Không thể nén dự án thành file .zip.\n", runner: runner)
            buildStatusText = "Lỗi nén .zip"
            return
        }

        let zipSize = zipData.count
        if zipSize > Self.maxCommunityUploadBytes {
            let sizeMB = String(format: "%.1f", Double(zipSize) / (1024.0 * 1024.0))
            appendLog(
                "[3012] Dự án sau khi nén (\(sizeMB) MB) vượt giới hạn 20 MB của Máy chủ Cộng đồng.\n" +
                "[3012] Gợi ý: Xoá bớt file nhị phân nặng trong dự án hoặc chuyển sang chế độ VPS SSH Cá nhân / Ngoại tuyến (.zip + GitHub Actions).\n",
                runner: runner
            )
            buildStatusText = "Vượt giới hạn 20 MB"
            return
        }

        let sizeKB = max(1, zipSize / 1024)
        appendLog("[3012] Đã nén sạch dự án (\(sizeKB) KB). Đang gửi lên \(primaryBase.absoluteString) (scheme: \(packageScheme.rawValue))...\n", runner: runner)
        buildStatusText = "Đang tải lên máy chủ build..."

        do {
            let uploadResult = try await performTheosRequest(
                primaryBaseURL: primaryBase,
                escapedPath: "v1/builds",
                method: "POST",
                headers: [
                    "Content-Type": "application/zip",
                    "X-Device-ID": deviceID,
                    "X-Package-Scheme": packageScheme.rawValue
                ],
                body: zipData,
                requestTimeout: 150,
                resourceTimeout: 240,
                maxAttempts: 4,
                onRetry: { [weak self] attempt, nextHost in
                    self?.appendLog("[3012] Kết nối gián đoạn khi tải lên, đang tự thử lại (lần \(attempt + 1)/4 -> \(nextHost))...\n", runner: runner)
                    self?.buildStatusText = "Đang kết nối lại máy chủ build (\(attempt + 1)/4)..."
                }
            )
            activeBuildBaseURL = uploadResult.usedBaseURL

            let http = uploadResult.response
            if !(200...299).contains(http.statusCode) {
                let apiErr = try? JSONDecoder().decode(TheosServerErrorResponse.self, from: uploadResult.data)
                let msg = apiErr?.message ?? "HTTP \(http.statusCode)"
                appendLog("[3012] Máy chủ từ chối build: \(msg)\n", runner: runner)
                buildStatusText = msg
                return
            }

            var job = try JSONDecoder().decode(TheosBuildJobResponse.self, from: uploadResult.data)
            activeJobID = job.id
            var logOffset = job.logOffset ?? 0
            if let initialLog = job.log, !initialLog.isEmpty {
                appendLog(initialLog, runner: runner)
            }

            // Poll job logs & status with resilient retry across transient drops
            var consecutivePollFailures = 0
            let maxConsecutivePollFailures = 8

            while !Task.isCancelled && (job.state == "queued" || job.state == "running") {
                if consecutivePollFailures == 0 {
                    if job.state == "queued" {
                        let pos = job.position ?? 1
                        buildStatusText = "Đang xếp hàng vị trí #\(pos)..."
                    } else {
                        buildStatusText = "Đang biên dịch Theos (.deb / .dylib)..."
                    }
                }

                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }

                let pollBase = activeBuildBaseURL ?? primaryBase
                do {
                    let pollResult = try await performTheosRequest(
                        primaryBaseURL: pollBase,
                        escapedPath: "v1/builds/\(job.id)",
                        queryItems: [URLQueryItem(name: "since", value: "\(logOffset)")],
                        method: "GET",
                        headers: ["X-Device-ID": deviceID],
                        requestTimeout: 20,
                        resourceTimeout: 35,
                        maxAttempts: 2
                    )
                    activeBuildBaseURL = pollResult.usedBaseURL

                    let pHttp = pollResult.response
                    if !(200...299).contains(pHttp.statusCode) {
                        if Self.isTransientGatewayStatus(pHttp.statusCode) && consecutivePollFailures < maxConsecutivePollFailures {
                            consecutivePollFailures += 1
                            buildStatusText = "Mạng chập chờn — đang giữ phiên build (\(consecutivePollFailures)/\(maxConsecutivePollFailures))..."
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            continue
                        }
                        if pHttp.statusCode == 404 {
                            appendLog("\n[3012] Phiên build đã hết hạn trên máy chủ.\n", runner: runner)
                            buildStatusText = "Build hết hạn"
                        } else {
                            let apiErr = try? JSONDecoder().decode(TheosServerErrorResponse.self, from: pollResult.data)
                            let msg = apiErr?.message ?? "HTTP \(pHttp.statusCode)"
                            appendLog("\n[3012] Lỗi máy chủ khi theo dõi build: \(msg)\n", runner: runner)
                            buildStatusText = msg
                        }
                        return
                    }

                    job = try JSONDecoder().decode(TheosBuildJobResponse.self, from: pollResult.data)
                    if consecutivePollFailures > 0 {
                        appendLog("\n[3012] Đã khôi phục kết nối theo dõi build.\n", runner: runner)
                    }
                    consecutivePollFailures = 0
                    if let nextOff = job.logOffset {
                        logOffset = nextOff
                    }
                    if let chunk = job.log, !chunk.isEmpty {
                        appendLog(chunk, runner: runner)
                    }
                } catch {
                    if Task.isCancelled { return }
                    if Self.isTransientNetworkError(error) && consecutivePollFailures < maxConsecutivePollFailures {
                        consecutivePollFailures += 1
                        if consecutivePollFailures == 1 {
                            appendLog("\n[3012] Mạng tạm gián đoạn, đang giữ phiên build và kết nối lại...\n", runner: runner)
                        }
                        buildStatusText = "Mạng chập chờn — đang giữ phiên build (\(consecutivePollFailures)/\(maxConsecutivePollFailures))..."
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        continue
                    }
                    throw error
                }
            }

            if Task.isCancelled { return }

            if job.state == "succeeded", let files = job.files, !files.isEmpty {
                buildStatusText = "Đang tải \(files.count) file kết quả về máy..."
                let packagesDir = workspaceRoot.appendingPathComponent("packages", isDirectory: true)
                try? FileManager.default.createDirectory(at: packagesDir, withIntermediateDirectories: true)

                var savedNames: [String] = []
                for f in files {
                    let dlBase = activeBuildBaseURL ?? primaryBase
                    let encodedFile = f.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? f.name
                    let dlResult = try await performTheosRequest(
                        primaryBaseURL: dlBase,
                        escapedPath: "v1/builds/\(job.id)/files/\(encodedFile)",
                        method: "GET",
                        headers: ["X-Device-ID": deviceID],
                        requestTimeout: 75,
                        resourceTimeout: 120,
                        maxAttempts: 4,
                        expectJSON: false,
                        onRetry: { [weak self] attempt, _ in
                            self?.buildStatusText = "Đang thử tải lại \(f.name) (\(attempt + 1)/4)..."
                        }
                    )
                    if dlResult.response.statusCode == 200 {
                        if Self.looksLikeUnexpectedHTML(data: dlResult.data, response: dlResult.response) {
                            appendLog("\n[3012] Máy chủ trả về trang HTML thay vì file \(f.name).\n", runner: runner)
                            continue
                        }
                        let safeName = (f.name as NSString).lastPathComponent
                        guard !safeName.isEmpty, safeName != ".", safeName != ".." else { continue }
                        let outURL = packagesDir.appendingPathComponent(safeName)
                        try dlResult.data.write(to: outURL, options: .atomic)
                        savedNames.append(safeName)
                    } else {
                        appendLog("\n[3012] Không tải được \(f.name) (HTTP \(dlResult.response.statusCode)).\n", runner: runner)
                    }
                }

                if savedNames.isEmpty {
                    buildStatusText = "Build xong nhưng không tải được file."
                } else {
                    let listText = savedNames.joined(separator: ", ")
                    appendLog("\n[3012] Đã tải về packages/: \(listText)\n", runner: runner)
                    buildStatusText = "Thành công: \(listText)"
                    onWorkspaceChanged()
                }
            } else {
                let errCode = job.error ?? job.state
                buildStatusText = "Build thất bại (\(errCode))"
            }
        } catch {
            if !Task.isCancelled {
                appendLog("\n[3012] Lỗi kết nối build server: \(error.localizedDescription)\n", runner: runner)
                buildStatusText = "Lỗi mạng"
            }
        }
    }

    // MARK: - Mode 2A: Direct Linux VPS Terminal (Live Make / Zero Re-Zip)
    private func buildViaDirectVPSTerminal(
        workspaceRoot: URL,
        sshService: SSHWorkspaceService,
        runner: CodeRunnerService,
        workspace: WorkspaceManager?,
        onWorkspaceChanged: @escaping () -> Void
    ) async {
        guard sshService.isConnected else {
            appendLog("[3012] Chưa kết nối SSH VPS. Hãy bấm 'Gắn VPS SSH' để đăng nhập VPS Linux.\n", runner: runner)
            buildStatusText = "Chưa kết nối SSH VPS"
            return
        }
        guard isTheosWorkspace(workspaceRoot) else {
            appendLog("[3012] Chưa tìm thấy Makefile / control trong dự án hiện tại.\n", runner: runner)
            buildStatusText = "Thiếu Makefile Theos"
            return
        }

        guard let prepared = await prepareRemoteProjectOnVPS(
            workspaceRoot: workspaceRoot,
            sshService: sshService,
            runner: runner,
            workspace: workspace
        ) else {
            return
        }

        let remoteDir = prepared.remoteDir
        lastRemoteBuildDir = remoteDir

        let capturedRoot = workspaceRoot
        let capturedRemoteDir = remoteDir
        sshService.onPTYMakeCompleted = { [weak self, weak sshService] exitCode in
            guard let self, let sshService else { return }
            Task { @MainActor in
                if exitCode == 0 {
                    await self.pullCompiledArtifactsFromVPS(
                        remoteProjectDir: capturedRemoteDir,
                        localWorkspaceRoot: capturedRoot,
                        sshService: sshService,
                        runner: runner,
                        onWorkspaceChanged: onWorkspaceChanged
                    )
                } else {
                    self.buildStatusText = "make trên VPS báo lỗi (exit \(exitCode))"
                    self.appendLog("\n[3012] make trên Terminal VPS thoát với mã lỗi \(exitCode).\n", runner: runner)
                }
            }
        }

        onOpenTerminalForLiveMake?()

        let schemeEnv = packageScheme == .rootful ? "" : " THEOS_PACKAGE_SCHEME=\(packageScheme.rawValue)"
        let quotedDir = SSHWorkspaceService.shellQuote(remoteDir)
        let cmd = "cd \(quotedDir) && ( [ -n \"$THEOS\" ] || for _t in \"$HOME/theos\" /opt/theos /var/theos /usr/local/theos; do [ -d \"$_t/makefiles\" ] && export THEOS=\"$_t\" && break; done ) && ( [ -f Makefile ] || { _mf=$(find . -maxdepth 4 -type f -name Makefile ! -path './.theos/*' | head -n 1); [ -n \"$_mf\" ] && cd \"$(dirname \"$_mf\")\"; } ) && make -j2 package FINALPACKAGE=1\(schemeEnv); __rc=$?; printf '\\n[3012-MAKE-EXIT:%d]\\n' $__rc"

        appendLog("[3012] Đã mở Terminal VPS và chạy make trực tiếp tại \(remoteDir)\n", runner: runner)
        buildStatusText = "Đang chạy make trực tiếp trên Terminal VPS..."
        sshService.sendPTYCommand(cmd)
    }

    // MARK: - Mode 2B: Private SSH VPS Build (Incremental Delta Sync + Persistent Workspace)
    private func buildViaPrivateSSHVPS(
        workspaceRoot: URL,
        sshService: SSHWorkspaceService,
        runner: CodeRunnerService,
        workspace: WorkspaceManager?,
        onWorkspaceChanged: @escaping () -> Void
    ) async {
        guard sshService.isConnected else {
            appendLog("[3012] Chưa kết nối SSH VPS. Hãy mở tab Remote SSH bên trái hoặc bấm 'Gắn VPS SSH' để đăng nhập VPS trước.\n", runner: runner)
            buildStatusText = "Chưa kết nối SSH VPS"
            return
        }
        guard isTheosWorkspace(workspaceRoot) else {
            appendLog("[3012] Chưa tìm thấy Makefile / control trong dự án hiện tại.\n", runner: runner)
            buildStatusText = "Thiếu Makefile Theos"
            return
        }

        guard let prepared = await prepareRemoteProjectOnVPS(
            workspaceRoot: workspaceRoot,
            sshService: sshService,
            runner: runner,
            workspace: workspace
        ) else {
            return
        }

        let remoteDir = prepared.remoteDir
        lastRemoteBuildDir = remoteDir
        let schemeArg = packageScheme == .rootful ? "" : "THEOS_PACKAGE_SCHEME=\(packageScheme.rawValue)"
        let quotedDir = SSHWorkspaceService.shellQuote(remoteDir)

        buildStatusText = "Đang biên dịch Theos trên VPS (giữ cache .theos)..."
        let buildScript = """
        if [ -z "$THEOS" ]; then
          for _t in "$HOME/theos" "/opt/theos" "/var/theos" "/usr/local/theos"; do
            [ -d "$_t/makefiles" ] && export THEOS="$_t" && break
          done
        fi
        cd \(quotedDir) && \
        if [ ! -f Makefile ]; then _mf=$(find . -maxdepth 4 -type f -name Makefile ! -path './.theos/*' | head -n 1); [ -n "$_mf" ] && cd "$(dirname "$_mf")"; fi && \
        make -j2 package FINALPACKAGE=1 \(schemeArg) 2>&1
        """
        let vpsOutput = await sshService.executeCommandOnVPS(buildScript)
        appendLog(vpsOutput + "\n", runner: runner)

        await pullCompiledArtifactsFromVPS(
            remoteProjectDir: remoteDir,
            localWorkspaceRoot: workspaceRoot,
            sshService: sshService,
            runner: runner,
            onWorkspaceChanged: onWorkspaceChanged
        )
    }

    private func prepareRemoteProjectOnVPS(
        workspaceRoot: URL,
        sshService: SSHWorkspaceService,
        runner: CodeRunnerService,
        workspace: WorkspaceManager?
    ) async -> (remoteDir: String, mountedLive: Bool)? {
        let dirtyBeforeSave: [(URL, String)] = workspace?.openTabs
            .filter(\.isDirty)
            .map { ($0.fileURL, $0.content) } ?? []
        workspace?.saveAllTabs()
        onBeforeRemoteMake?()

        if let mountedRemote = sshService.remoteDirectoryBound(to: workspaceRoot) {
            buildStatusText = "Đang đồng bộ SFTP tab vừa lưu..."
            await sshService.flushPendingSFTPWrites(extraDirtyFiles: dirtyBeforeSave)
            lastRemoteBuildDir = mountedRemote
            appendLog("[3012] Dự án đang mở trực tiếp từ VPS (\(mountedRemote)) — không cần gửi file zip.\n", runner: runner)
            return (mountedRemote, true)
        }

        buildStatusText = "Đang kiểm tra file thay đổi (SHA-256 delta)..."
        let slug = Self.sanitizeRemoteSlug(workspaceRoot.lastPathComponent)
        let homeOut = await sshService.executeCommandOnVPS("printf '%s' \"$HOME\"").trimmingCharacters(in: .whitespacesAndNewlines)
        let homeBase = (homeOut.isEmpty || homeOut.contains("[SSH Error]") || !homeOut.hasPrefix("/")) ? "/tmp" : homeOut
        let remoteProjDir = "\(homeBase)/3012-Workspaces/\(slug)"
        let quotedProjDir = SSHWorkspaceService.shellQuote(remoteProjDir)

        let mkdirOut = await sshService.executeCommandOnVPS("mkdir -p \(quotedProjDir)")
        if mkdirOut.contains("[Process exited with code") || mkdirOut.hasPrefix("[SSH Error]") {
            appendLog(mkdirOut + "\n", runner: runner)
            buildStatusText = "Không tạo được workspace trên VPS"
            return nil
        }

        let localFiles = await Task.detached(priority: .userInitiated) {
            Self.collectCleanLocalFiles(in: workspaceRoot)
        }.value

        let hashCmd = "cd \(quotedProjDir) && find . -type f ! -path './.theos/*' ! -path './packages/*' ! -path './.git/*' -exec sha256sum {} + 2>/dev/null || true"
        let hashOut = await sshService.executeCommandOnVPS(hashCmd)
        var remoteHashes: [String: String] = [:]
        for line in hashOut.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count > 66 else { continue }
            let hex = String(trimmed.prefix(64)).lowercased()
            guard hex.allSatisfy({ ($0 >= "0" && $0 <= "9") || ($0 >= "a" && $0 <= "f") }) else { continue }
            var pathPart = String(trimmed.dropFirst(64)).trimmingCharacters(in: .whitespaces)
            if pathPart.hasPrefix("*") { pathPart.removeFirst() }
            if pathPart.hasPrefix("./") { pathPart.removeFirst(2) }
            guard !pathPart.isEmpty else { continue }
            remoteHashes[pathPart] = hex
        }

        let changedFiles = localFiles.filter { remoteHashes[$0.relPath] != $0.sha256Hex }
        let localRelSet = Set(localFiles.map(\.relPath))
        let staleRemoteFiles = Set(remoteHashes.keys).subtracting(localRelSet).sorted()

        if !staleRemoteFiles.isEmpty {
            var idx = 0
            while idx < staleRemoteFiles.count {
                let slice = staleRemoteFiles[idx..<min(idx + 40, staleRemoteFiles.count)]
                let joinedArgs = slice.map { SSHWorkspaceService.shellQuote("./\($0)") }.joined(separator: " ")
                _ = await sshService.executeCommandOnVPS("cd \(quotedProjDir) && rm -f \(joinedArgs)")
                idx += 40
            }
        }

        if changedFiles.isEmpty {
            appendLog("[3012] 0 file thay đổi (delta sync 0 KB) — giữ nguyên cache tại \(remoteProjDir)\n", runner: runner)
        } else {
            let neededDirs = Array(Set(changedFiles.compactMap { file -> String? in
                let parent = (file.relPath as NSString).deletingLastPathComponent
                return (parent.isEmpty || parent == ".") ? nil : "./\(parent)"
            })).sorted()

            if !neededDirs.isEmpty {
                var dIdx = 0
                while dIdx < neededDirs.count {
                    let slice = neededDirs[dIdx..<min(dIdx + 40, neededDirs.count)]
                    let joinedDirs = slice.map { SSHWorkspaceService.shellQuote($0) }.joined(separator: " ")
                    _ = await sshService.executeCommandOnVPS("cd \(quotedProjDir) && mkdir -p \(joinedDirs)")
                    dIdx += 40
                }
            }

            let totalBytes = changedFiles.reduce(0) { $0 + $1.data.count }
            let kb = max(1, totalBytes / 1024)
            appendLog("[3012] Đồng bộ delta \(changedFiles.count)/\(localFiles.count) file thay đổi (\(kb) KB) -> \(remoteProjDir)...\n", runner: runner)
            buildStatusText = "Đang đồng bộ \(changedFiles.count) file thay đổi..."

            for file in changedFiles {
                do {
                    try await sshService.uploadDataViaSFTP(data: file.data, remotePath: "\(remoteProjDir)/\(file.relPath)")
                } catch {
                    appendLog("[3012] Lỗi upload SFTP (\(file.relPath)): \(error.localizedDescription)\n", runner: runner)
                    buildStatusText = "Lỗi đồng bộ SFTP"
                    return nil
                }
            }
        }

        lastRemoteBuildDir = remoteProjDir
        return (remoteProjDir, false)
    }

    public func pullCompiledArtifactsFromVPS(
        remoteProjectDir: String? = nil,
        localWorkspaceRoot: URL,
        sshService: SSHWorkspaceService,
        runner: CodeRunnerService,
        onWorkspaceChanged: @escaping () -> Void
    ) async {
        guard sshService.isConnected else {
            buildStatusText = "Chưa kết nối SSH VPS"
            return
        }
        guard let searchDir = remoteProjectDir ?? lastRemoteBuildDir ?? sshService.remoteDirectoryBound(to: localWorkspaceRoot),
              !searchDir.isEmpty else {
            appendLog("[3012] Chưa xác định thư mục build trên VPS. Hãy chạy make trước hoặc gắn thư mục VPS.\n", runner: runner)
            buildStatusText = "Chưa có thư mục build trên VPS"
            return
        }

        let quotedDir = SSHWorkspaceService.shellQuote(searchDir)
        let listOut = await sshService.executeCommandOnVPS(
            "find \(quotedDir) -type f \\( -name '*.deb' -o -name '*.dylib' \\) ! -path '*/.theos/obj/*' -print 2>/dev/null"
        )
        let remoteArtifacts = listOut
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && ($0.hasSuffix(".deb") || $0.hasSuffix(".dylib")) }

        guard !remoteArtifacts.isEmpty else {
            buildStatusText = "Chưa thấy .deb/.dylib trong \(searchDir)"
            appendLog("[3012] Không tìm thấy file .deb/.dylib trong \(searchDir) (hãy kiểm tra lại output của make).\n", runner: runner)
            return
        }

        let packagesDir = localWorkspaceRoot.appendingPathComponent("packages", isDirectory: true)
        try? FileManager.default.createDirectory(at: packagesDir, withIntermediateDirectories: true)

        var fetched: [String] = []
        for path in remoteArtifacts {
            let fileName = (path as NSString).lastPathComponent
            guard !fileName.isEmpty, fileName != ".", fileName != ".." else { continue }
            if let decoded = try? await sshService.downloadDataViaSFTP(remotePath: path) {
                try? decoded.write(to: packagesDir.appendingPathComponent(fileName), options: .atomic)
                fetched.append(fileName)
            }
        }

        refreshLocalPackages(in: localWorkspaceRoot)
        if fetched.isEmpty {
            buildStatusText = "Không tải được .deb/.dylib từ VPS"
        } else {
            let summary = fetched.joined(separator: ", ")
            appendLog("[3012] Đã tải từ VPS về packages/: \(summary)\n", runner: runner)
            buildStatusText = "Thành công (VPS): \(summary)"
            onWorkspaceChanged()
        }
    }

    // MARK: - Mode 3: Offline GitHub Actions + Clean .zip Export
    private func exportOfflineGitHubPackage(
        workspaceRoot: URL,
        runner: CodeRunnerService,
        onWorkspaceChanged: @escaping () -> Void
    ) async {
        let fm = FileManager.default
        let workflowPath = workspaceRoot.appendingPathComponent(".github/workflows/theos-build.yml")
        try? fm.createDirectory(at: workflowPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Self.githubWorkflowTemplate(scheme: packageScheme).write(to: workflowPath, atomically: true, encoding: .utf8)

        guard let zipData = await Task.detached(priority: .userInitiated, operation: { () -> Data? in
            Self.createCleanTheosZipData(workspaceRoot: workspaceRoot)
        }).value else {
            appendLog("[3012] Lỗi đóng gói .zip ngoại tuyến.\n", runner: runner)
            buildStatusText = "Lỗi nén .zip"
            return
        }

        let packagesDir = workspaceRoot.appendingPathComponent("packages", isDirectory: true)
        try? fm.createDirectory(at: packagesDir, withIntermediateDirectories: true)
        let archiveName = "\(workspaceRoot.lastPathComponent)-Theos.zip"
        let outURL = packagesDir.appendingPathComponent(archiveName)
        do {
            try zipData.write(to: outURL, options: .atomic)
            appendLog("[3012] Đã tạo .github/workflows/theos-build.yml và đóng gói sẵn sàng tại packages/\(archiveName).\n", runner: runner)
            buildStatusText = "Đã xuất \(archiveName)"
            onWorkspaceChanged()
        } catch {
            appendLog("[3012] Không ghi được file .zip: \(error.localizedDescription)\n", runner: runner)
            buildStatusText = "Lỗi ghi file"
        }
    }

    @MainActor
    @discardableResult
    public func syncMakefileSourceFiles(
        in workspace: WorkspaceManager,
        projectRoot: URL? = nil,
        isEnglish: Bool = false
    ) -> String {
        let fm = FileManager.default
        let rootURL = (projectRoot ?? workspace.rootURL).standardizedFileURL
        let makefileURL = ["Makefile", "GNUmakefile"]
            .map { rootURL.appendingPathComponent($0) }
            .first(where: { fm.fileExists(atPath: $0.path) })

        guard let targetURL = makefileURL,
              let rawContent = try? String(contentsOf: targetURL, encoding: .utf8) else {
            return isEnglish
                ? "Makefile not found in project root."
                : "Chưa thấy file Makefile / GNUmakefile ở thư mục gốc."
        }

        let excludedDirs: Set<String> = [".git", ".theos", "packages", ".build", "node_modules", "__MACOSX"]
        let sourceExts: Set<String> = ["x", "xm", "xi", "xmi", "m", "mm", "c", "cpp", "cc", "cxx"]
        let headerExts: Set<String> = ["h", "hpp", "hh"]

        var sourceFiles: [String] = []
        var headerDirs: Set<String> = []
        let rootCanon = WorkspaceManager.canonicalPath(rootURL)
        let rootPrefix = rootCanon == "/" ? "/" : rootCanon + "/"

        if let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator {
                let name = url.lastPathComponent
                if excludedDirs.contains(name) || name.hasPrefix(".3012") {
                    enumerator.skipDescendants()
                    continue
                }
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDir { continue }

                let itemCanon = WorkspaceManager.canonicalPath(url)
                guard itemCanon.hasPrefix(rootPrefix) else { continue }
                let relPath = String(itemCanon.dropFirst(rootPrefix.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if relPath.isEmpty { continue }

                let ext = url.pathExtension.lowercased()
                if sourceExts.contains(ext) {
                    sourceFiles.append(relPath)
                } else if headerExts.contains(ext) {
                    let parentRel = (relPath as NSString).deletingLastPathComponent
                    if !parentRel.isEmpty && parentRel != "." {
                        headerDirs.insert(parentRel)
                    }
                }
            }
        }

        guard !sourceFiles.isEmpty else {
            return isEnglish
                ? "No .x/.xm/.m/.mm/.c/.cpp source files found in workspace."
                : "Không tìm thấy file nguồn .x/.xm/.m/.mm/.c/.cpp nào trong thư mục dự án."
        }

        let sortedSources = sourceFiles.sorted { a, b in
            let priorityNames = ["tweak.x", "tweak.xm", "main.m", "main.mm", "main.c"]
            let aPri = priorityNames.contains((a as NSString).lastPathComponent.lowercased()) ? 0 : 1
            let bPri = priorityNames.contains((b as NSString).lastPathComponent.lowercased()) ? 0 : 1
            if aPri != bPri { return aPri < bPri }
            return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }

        let lines = rawContent.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")

        // Detect TWEAK_NAME or existing *_FILES prefix
        var detectedName: String? = nil
        var existingFilesPrefix: String? = nil
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") || trimmed.isEmpty { continue }
            if detectedName == nil, let eqRange = trimmed.range(of: "=") {
                let lhsRaw = trimmed[..<eqRange.lowerBound].trimmingCharacters(in: CharacterSet(charactersIn: " :+?"))
                if lhsRaw == "TWEAK_NAME" || lhsRaw == "APPLICATION_NAME" || lhsRaw == "TOOL_NAME" {
                    let val = trimmed[eqRange.upperBound...].trimmingCharacters(in: .whitespaces)
                    if let firstToken = val.split(separator: " ").first, !firstToken.isEmpty {
                        detectedName = String(firstToken)
                    }
                } else if lhsRaw.hasSuffix("_FILES") && existingFilesPrefix == nil {
                    existingFilesPrefix = String(lhsRaw.dropLast(6))
                }
            }
        }

        let targetName = detectedName ?? existingFilesPrefix ?? "Tweak3012"
        let filesKey = "\(targetName)_FILES"
        let cflagsKey = "\(targetName)_CFLAGS"
        let replacementFilesLine = "\(filesKey) = \(sortedSources.joined(separator: " "))"

        var newLines: [String] = []
        var didReplaceFiles = false
        var didUpdateCflags = false
        let missingIncludeFlags = headerDirs.sorted().map { "-I./\($0)" }.filter { !rawContent.contains($0) }

        var idx = 0
        while idx < lines.count {
            let line = lines[idx]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isComment = trimmed.hasPrefix("#")

            if !isComment, !didReplaceFiles, let eqRange = trimmed.range(of: "=") {
                let lhs = trimmed[..<eqRange.lowerBound].trimmingCharacters(in: CharacterSet(charactersIn: " :+?"))
                let matchesExistingFiles = existingFilesPrefix.map { lhs == "\($0)_FILES" } ?? false
                if lhs == filesKey || matchesExistingFiles {
                    // Consume any trailing backslash-continuation lines
                    while idx < lines.count - 1 && lines[idx].trimmingCharacters(in: .whitespaces).hasSuffix("\\") {
                        idx += 1
                    }
                    newLines.append(replacementFilesLine)
                    didReplaceFiles = true
                    idx += 1
                    continue
                }
                if lhs == cflagsKey, !missingIncludeFlags.isEmpty, !didUpdateCflags {
                    newLines.append("\(line) \(missingIncludeFlags.joined(separator: " "))")
                    didUpdateCflags = true
                    idx += 1
                    continue
                }
            }

            newLines.append(line)
            idx += 1
        }

        if !didReplaceFiles {
            if let includeIdx = newLines.lastIndex(where: { $0.contains("tweak.mk") || $0.contains("application.mk") || $0.contains("tool.mk") }) {
                newLines.insert(replacementFilesLine, at: includeIdx)
            } else {
                newLines.append(replacementFilesLine)
            }
        }
        if !missingIncludeFlags.isEmpty && !didUpdateCflags {
            let extraFlagsLine = "\(cflagsKey) += \(missingIncludeFlags.joined(separator: " "))"
            if let includeIdx = newLines.lastIndex(where: { $0.contains("tweak.mk") || $0.contains("application.mk") || $0.contains("tool.mk") }) {
                newLines.insert(extraFlagsLine, at: includeIdx)
            } else {
                newLines.append(extraFlagsLine)
            }
        }

        let updatedContent = newLines.joined(separator: "\n")
        do {
            try updatedContent.write(to: targetURL, atomically: true, encoding: .utf8)
            workspace.reloadTree()
            if let tabIdx = workspace.openTabs.firstIndex(where: { $0.fileURL.standardizedFileURL == targetURL.standardizedFileURL }) {
                workspace.openTabs[tabIdx].content = updatedContent
                workspace.openTabs[tabIdx].savedContent = updatedContent
            }
            workspace.onFileSavedOrChanged?()
            if !workspace.suppressOutboundSyncEvents,
               let rel = workspace.relativePathIfInsideRoot(targetURL) {
                workspace.onWorkspaceMutation?(.upsertFile(relativePath: rel, content: updatedContent))
            }
            let flagNote = missingIncludeFlags.isEmpty ? "" : " (\(missingIncludeFlags.joined(separator: " ")))"
            return isEnglish
                ? "Synced \(sortedSources.count) source file(s) into \(filesKey)\(flagNote)."
                : "Đã đồng bộ \(sortedSources.count) file nguồn vào \(filesKey)\(flagNote)."
        } catch {
            return isEnglish
                ? "Failed to write Makefile: \(error.localizedDescription)"
                : "Không ghi được Makefile: \(error.localizedDescription)"
        }
    }

    // MARK: - Resilient Networking Helpers
    nonisolated private static func isMisconfiguredRootHost(_ rawURL: String) -> Bool {
        var candidate = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return false }
        if !candidate.contains("://") {
            candidate = "https://" + candidate
        }
        return URL(string: candidate)?.host?.lowercased() == "kaydus.xyz"
    }

    nonisolated private static func looksLikeUnexpectedHTML(data: Data, response: HTTPURLResponse) -> Bool {
        if let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
           contentType.contains("text/html") || contentType.contains("application/xhtml") {
            return true
        }
        let head = String(decoding: data.prefix(256), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return head.hasPrefix("<!doctype html") || head.hasPrefix("<html")
    }

    nonisolated private static func makeEphemeralTheosSession(
        requestTimeout: TimeInterval,
        resourceTimeout: TimeInterval
    ) -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.waitsForConnectivity = false
        cfg.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        cfg.urlCache = nil
        cfg.httpMaximumConnectionsPerHost = 2
        cfg.timeoutIntervalForRequest = requestTimeout
        cfg.timeoutIntervalForResource = resourceTimeout
        let appVer = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "5.4.0"
        cfg.httpAdditionalHeaders = [
            "User-Agent": "3012/\(appVer) (iOS)",
            "Accept": "application/json, application/octet-stream;q=0.9, */*;q=0.8"
        ]
        return URLSession(configuration: cfg)
    }

    nonisolated private static func isTransientNetworkError(_ error: Error) -> Bool {
        if error is CancellationError { return false }
        let nsErr = error as NSError
        if nsErr.domain == NSURLErrorDomain {
            switch URLError.Code(rawValue: nsErr.code) {
            case .networkConnectionLost,
                 .timedOut,
                 .cannotConnectToHost,
                 .cannotFindHost,
                 .dnsLookupFailed,
                 .notConnectedToInternet,
                 .secureConnectionFailed,
                 .cannotLoadFromNetwork:
                return true
            default:
                break
            }
        }
        return false
    }

    nonisolated private static func isTransientGatewayStatus(_ statusCode: Int) -> Bool {
        statusCode == 502 || statusCode == 504 || (520...524).contains(statusCode)
    }

    private func candidateBaseURLs(for primary: URL) -> [URL] {
        if primary.host?.lowercased() == "kaydus.xyz", let def = URL(string: Self.defaultServerURL) {
            return [def]
        }
        return [primary]
    }

    private func performTheosRequest(
        primaryBaseURL: URL,
        escapedPath: String,
        queryItems: [URLQueryItem] = [],
        method: String,
        headers: [String: String] = [:],
        body: Data? = nil,
        requestTimeout: TimeInterval,
        resourceTimeout: TimeInterval,
        maxAttempts: Int,
        expectJSON: Bool = true,
        onRetry: ((Int, String) -> Void)? = nil
    ) async throws -> (data: Data, response: HTTPURLResponse, usedBaseURL: URL) {
        let candidates = candidateBaseURLs(for: primaryBaseURL)
        let totalAttempts = max(1, maxAttempts)
        var lastError: Error = URLError(.cannotConnectToHost)

        for attempt in 1...totalAttempts {
            try Task.checkCancellation()
            let base = candidates[(attempt - 1) % candidates.count]
            var rawBase = base.absoluteString
            while rawBase.hasSuffix("/") { rawBase.removeLast() }
            let cleanPath = escapedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let joined = cleanPath.isEmpty ? rawBase : "\(rawBase)/\(cleanPath)"

            let finalURL: URL
            if queryItems.isEmpty {
                guard let url = URL(string: joined) else {
                    throw URLError(.badURL)
                }
                finalURL = url
            } else {
                var comps = URLComponents(string: joined)
                comps?.queryItems = queryItems
                guard let url = comps?.url else {
                    throw URLError(.badURL)
                }
                finalURL = url
            }

            var req = URLRequest(url: finalURL)
            req.httpMethod = method
            req.timeoutInterval = requestTimeout
            req.assumesHTTP3Capable = false
            req.setValue("close", forHTTPHeaderField: "Connection")
            for (k, v) in headers {
                req.setValue(v, forHTTPHeaderField: k)
            }

            var tempUploadURL: URL?
            if let body {
                let tmpURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("3012_up_\(UUID().uuidString).bin")
                try body.write(to: tmpURL, options: .atomic)
                tempUploadURL = tmpURL
            }
            defer {
                if let tempUploadURL {
                    try? FileManager.default.removeItem(at: tempUploadURL)
                }
            }

            let session = Self.makeEphemeralTheosSession(
                requestTimeout: requestTimeout,
                resourceTimeout: resourceTimeout
            )
            defer { session.finishTasksAndInvalidate() }

            do {
                let (data, resp): (Data, URLResponse)
                if let tempUploadURL {
                    (data, resp) = try await session.upload(for: req, fromFile: tempUploadURL)
                } else {
                    (data, resp) = try await session.data(for: req)
                }
                guard let http = resp as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                if expectJSON && Self.looksLikeUnexpectedHTML(data: data, response: http) {
                    let htmlErr = NSError(
                        domain: "TheosBuildService",
                        code: 502,
                        userInfo: [NSLocalizedDescriptionKey: "Máy chủ trả về HTML thay vì JSON API (hãy dùng https://build.kaydus.xyz)."]
                    )
                    lastError = htmlErr
                    if attempt < totalAttempts {
                        let nextBase = candidates[attempt % candidates.count]
                        onRetry?(attempt, nextBase.host ?? nextBase.absoluteString)
                        try? await Task.sleep(nanoseconds: UInt64(attempt) * 650_000_000)
                        continue
                    }
                    throw htmlErr
                }
                if Self.isTransientGatewayStatus(http.statusCode) && attempt < totalAttempts {
                    let nextBase = candidates[attempt % candidates.count]
                    onRetry?(attempt, nextBase.host ?? nextBase.absoluteString)
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 650_000_000)
                    continue
                }
                return (data, http, base)
            } catch {
                if error is CancellationError || Task.isCancelled {
                    throw error
                }
                lastError = error
                if Self.isTransientNetworkError(error) && attempt < totalAttempts {
                    let nextBase = candidates[attempt % candidates.count]
                    onRetry?(attempt, nextBase.host ?? nextBase.absoluteString)
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 650_000_000)
                    continue
                }
                throw error
            }
        }
        throw lastError
    }

    // MARK: - Helpers
    private func appendLog(_ text: String, runner: CodeRunnerService?) {
        buildLog += text
        if buildLog.count > 120_000 {
            buildLog = String(buildLog.suffix(100_000))
        }
        runner?.consoleOutput = buildLog
    }

    private func normalizedBaseURL() -> URL? {
        var raw = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty || Self.isMisconfiguredRootHost(raw) {
            raw = Self.defaultServerURL
        }
        if !raw.hasPrefix("http://") && !raw.hasPrefix("https://") {
            raw = "https://" + raw
        }
        while raw.hasSuffix("/") { raw.removeLast() }
        return URL(string: raw)
    }

    private struct LocalDeltaFile: Sendable {
        let relPath: String
        let sha256Hex: String
        let data: Data
    }

    nonisolated private static func sanitizeRemoteSlug(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let cleaned = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : Character("-") }
        let collapsed = String(cleaned).trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        return collapsed.isEmpty ? "project" : String(collapsed.prefix(48))
    }

    nonisolated private static func collectCleanLocalFiles(in workspaceRoot: URL) -> [LocalDeltaFile] {
        let fm = FileManager.default
        let excludedDirs: Set<String> = [
            ".git", ".theos", "packages", ".build", "build",
            "node_modules", "__MACOSX", ".swiftpm", "DerivedData", "__pycache__"
        ]
        let excludedDirSuffixes = [".dsym", ".xcarchive"]
        let excludedFileExts: Set<String> = ["ipa", "tipa", "deb", "dmg", "iso"]
        let canonicalRoot = WorkspaceManager.canonicalPath(workspaceRoot)
        let rootPrefix = canonicalRoot == "/" ? "/" : canonicalRoot + "/"

        var results: [LocalDeltaFile] = []
        guard let enumerator = fm.enumerator(
            at: workspaceRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) else {
            return results
        }

        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            let lowerName = name.lowercased()
            if excludedDirs.contains(name)
                || excludedDirSuffixes.contains(where: { lowerName.hasSuffix($0) })
                || name.hasPrefix(".3012")
                || name == ".DS_Store" {
                enumerator.skipDescendants()
                continue
            }
            let rv = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            let isDir = rv?.isDirectory ?? false
            if rv?.isSymbolicLink == true {
                if isDir { enumerator.skipDescendants() }
                continue
            }
            if isDir { continue }

            let ext = url.pathExtension.lowercased()
            if excludedFileExts.contains(ext) || lowerName.hasSuffix("-theos.zip") {
                continue
            }

            let canonicalItem = WorkspaceManager.canonicalPath(url)
            guard canonicalItem.hasPrefix(rootPrefix) else { continue }
            let rel = String(canonicalItem.dropFirst(rootPrefix.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !rel.isEmpty, !rel.contains("..") else { continue }
            guard let data = try? Data(contentsOf: url) else { continue }
            let digest = SHA256.hash(data: data)
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            results.append(LocalDeltaFile(relPath: rel, sha256Hex: hex, data: data))
        }
        return results
    }

    nonisolated private static func createCleanTheosZipData(workspaceRoot: URL) -> Data? {
        let fm = FileManager.default
        let stageID = UUID().uuidString
        let stageParent = fm.temporaryDirectory.appendingPathComponent("3012_stage_\(stageID)", isDirectory: true)
        let projectStage = stageParent.appendingPathComponent(workspaceRoot.lastPathComponent, isDirectory: true)
        let destZip = fm.temporaryDirectory.appendingPathComponent("3012_theos_\(stageID).zip")

        defer {
            try? fm.removeItem(at: stageParent)
            try? fm.removeItem(at: destZip)
        }

        do {
            try fm.createDirectory(at: projectStage, withIntermediateDirectories: true)
            let excludedDirs: Set<String> = [
                ".git", ".theos", "packages", ".build", "build",
                "node_modules", "__MACOSX", ".swiftpm", "DerivedData", "__pycache__"
            ]
            let excludedDirSuffixes = [".dsym", ".xcarchive"]
            let excludedFileExts: Set<String> = ["ipa", "tipa", "deb", "dmg", "iso"]
            let canonicalRoot = WorkspaceManager.canonicalPath(workspaceRoot)
            let rootPrefix = canonicalRoot == "/" ? "/" : canonicalRoot + "/"
            if let enumerator = fm.enumerator(
                at: workspaceRoot,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: []
            ) {
                for case let url as URL in enumerator {
                    let name = url.lastPathComponent
                    let lowerName = name.lowercased()
                    if excludedDirs.contains(name)
                        || excludedDirSuffixes.contains(where: { lowerName.hasSuffix($0) })
                        || name.hasPrefix(".3012")
                        || name == ".DS_Store" {
                        enumerator.skipDescendants()
                        continue
                    }
                    let rv = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                    let isDir = rv?.isDirectory ?? false
                    if rv?.isSymbolicLink == true {
                        if isDir { enumerator.skipDescendants() }
                        continue
                    }
                    if !isDir {
                        let ext = url.pathExtension.lowercased()
                        if excludedFileExts.contains(ext) || lowerName.hasSuffix("-theos.zip") {
                            continue
                        }
                    }
                    let canonicalItem = WorkspaceManager.canonicalPath(url)
                    guard canonicalItem.hasPrefix(rootPrefix) else {
                        if isDir { enumerator.skipDescendants() }
                        continue
                    }
                    let rel = String(canonicalItem.dropFirst(rootPrefix.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
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

    nonisolated private static func escapeXML(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func sanitizeSymbolName(_ raw: String, fallback: String) -> String {
        let allowed = raw.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0 == "_"
        }
        var out = String(String.UnicodeScalarView(allowed))
        if let first = out.first, first.isNumber {
            out = "T" + out
        }
        return out.isEmpty ? fallback : out
    }

    private static func githubWorkflowTemplate(scheme: TheosPackageScheme) -> String {
        let schemeLine = scheme == .rootful ? "" : " THEOS_PACKAGE_SCHEME=\(scheme.rawValue)"
        return """
        name: Build Theos Tweak

        on:
          workflow_dispatch:
          push:

        jobs:
          build:
            runs-on: ubuntu-22.04
            container:
              image: ghcr.io/theos/theos:latest
            steps:
              - uses: actions/checkout@v4
              - name: Build .deb & .dylib
                run: make -j2 package FINALPACKAGE=1\(schemeLine)
              - uses: actions/upload-artifact@v4
                with:
                  name: theos-packages
                  path: |
                    packages/*.deb
                    .theos/obj/*.dylib
        """
    }
}
