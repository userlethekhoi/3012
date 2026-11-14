import Foundation
import SwiftUI
import ZIPFoundation

public enum TheosBuildMode: String, CaseIterable, Identifiable, Codable {
    case communityServer = "communityServer"
    case privateSSHVPS = "privateSSHVPS"
    case offlineExport = "offlineExport"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .communityServer: return L10n.tr("Máy chủ Cộng đồng (Không cần JB / VPS)", "Community Build Server (No JB / VPS Needed)")
        case .privateSSHVPS: return L10n.tr("VPS SSH Cá nhân (Qua kết nối SSH)", "Private SSH VPS (Via SSH Connection)")
        case .offlineExport: return L10n.tr("Ngoại tuyến (.zip + GitHub Actions)", "Offline Export (.zip + GitHub Actions)")
        }
    }

    public var subtitle: String {
        switch self {
        case .communityServer: return L10n.tr("Biên dịch cách ly trong container Docker (--network none, không lưu code)", "Isolated Docker sandbox (--network none, ephemeral RAM build)")
        case .privateSSHVPS: return L10n.tr("Chạy make package trực tiếp trên VPS Linux riêng qua SSH", "Runs make package directly on your private Linux VPS via SSH")
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
    public static let alternateServerURL = "https://kaydus.xyz"

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

    private var activeTask: Task<Void, Never>?
    private var activeJobID: String?
    private let deviceID: String

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
        self.serverURL = storedURL.isEmpty ? Self.defaultServerURL : storedURL
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
        let makefileURL = rootURL.appendingPathComponent("Makefile")
        let controlURL = rootURL.appendingPathComponent("control")
        if fm.fileExists(atPath: makefileURL.path) && fm.fileExists(atPath: controlURL.path) {
            return true
        }
        if let makefileText = try? String(contentsOf: makefileURL, encoding: .utf8),
           makefileText.contains("THEOS") {
            return true
        }
        let entries = (try? fm.contentsOfDirectory(atPath: rootURL.path)) ?? []
        return entries.contains { name in
            let lower = name.lowercased()
            return lower.hasSuffix(".x") || lower.hasSuffix(".xm")
        }
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
        let cleanPkgID = rawBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "com.dev.\(cleanName.lowercased())"
            : rawBundleID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanFilter = rawFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "com.apple.springboard"
            : rawFilter.trimmingCharacters(in: .whitespacesAndNewlines)

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
        \t\t\t<string>\(cleanFilter)</string>
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
            try? entry.content.write(to: dest, atomically: true, encoding: .utf8)
        }
        workspace.reloadTree()

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
        guard let endpoint = normalizedBaseURL()?.appendingPathComponent("v1/health") else {
            serverHealthSummary = "URL máy chủ không hợp lệ."
            return
        }
        var req = URLRequest(url: endpoint)
        req.timeoutInterval = 10
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let health = try? JSONDecoder().decode(TheosHealthResponse.self, from: data),
                  health.ok else {
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                serverHealthSummary = "Máy chủ phản hồi lỗi HTTP \(code)."
                return
            }
            let running = health.running ?? 0
            let capacity = health.capacity ?? 2
            let queued = health.queued ?? 0
            let ver = health.version ?? "1.0"
            serverHealthSummary = "Online v\(ver) — Đang chạy \(running)/\(capacity) • Hàng đợi: \(queued)"
        } catch {
            serverHealthSummary = "Không kết nối được: \(error.localizedDescription)"
        }
    }

    // MARK: - Build Orchestration
    public func startBuild(
        workspaceRoot: URL,
        sshService: SSHWorkspaceService,
        runner: CodeRunnerService,
        onWorkspaceChanged: @escaping () -> Void
    ) {
        guard !isBuilding else { return }
        activeTask?.cancel()

        isBuilding = true
        buildLog = "[3012 Theos] Chuẩn bị đóng gói dự án từ \(workspaceRoot.lastPathComponent)...\n"
        buildStatusText = "Đang đóng gói mã nguồn..."
        runner.consoleOutput = buildLog

        activeTask = Task { [weak self] () -> Void in
            guard let self else { return }
            defer {
                self.isBuilding = false
                self.activeJobID = nil
                self.refreshLocalPackages(in: workspaceRoot)
                onWorkspaceChanged()
            }

            switch self.buildMode {
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
        activeTask?.cancel()
        activeTask = nil
        isBuilding = false
        buildStatusText = "Đã huỷ build."
        appendLog("\n[3012] Người dùng đã huỷ tiến trình build.\n", runner: nil)

        if let jobID = jobToCancel, let base = normalizedBaseURL() {
            let deleteURL = base.appendingPathComponent("v1/builds/\(jobID)")
            let dev = deviceID
            Task {
                var req = URLRequest(url: deleteURL)
                req.httpMethod = "DELETE"
                req.setValue(dev, forHTTPHeaderField: "X-Device-ID")
                _ = try? await URLSession.shared.data(for: req)
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
        guard let baseURL = normalizedBaseURL() else {
            appendLog("[3012] URL Build Server không hợp lệ.\n", runner: runner)
            buildStatusText = "Sai URL máy chủ"
            return
        }

        guard let zipData = createCleanTheosZipData(workspaceRoot: workspaceRoot) else {
            appendLog("[3012] Không thể nén dự án thành file .zip.\n", runner: runner)
            buildStatusText = "Lỗi nén .zip"
            return
        }

        let sizeKB = max(1, zipData.count / 1024)
        appendLog("[3012] Đã nén sạch dự án (\(sizeKB) KB). Đang gửi lên \(baseURL.absoluteString) (scheme: \(packageScheme.rawValue))...\n", runner: runner)
        buildStatusText = "Đang tải lên máy chủ build..."

        var postReq = URLRequest(url: baseURL.appendingPathComponent("v1/builds"))
        postReq.httpMethod = "POST"
        postReq.timeoutInterval = 45
        postReq.setValue("application/zip", forHTTPHeaderField: "Content-Type")
        postReq.setValue(deviceID, forHTTPHeaderField: "X-Device-ID")
        postReq.setValue(packageScheme.rawValue, forHTTPHeaderField: "X-Package-Scheme")
        postReq.httpBody = zipData

        do {
            let (postData, postResp) = try await URLSession.shared.data(for: postReq)
            guard let http = postResp as? HTTPURLResponse else {
                appendLog("[3012] Phản hồi không hợp lệ từ máy chủ.\n", runner: runner)
                buildStatusText = "Lỗi kết nối"
                return
            }

            if !(200...299).contains(http.statusCode) {
                let apiErr = try? JSONDecoder().decode(TheosServerErrorResponse.self, from: postData)
                let msg = apiErr?.message ?? "HTTP \(http.statusCode)"
                appendLog("[3012] Máy chủ từ chối build: \(msg)\n", runner: runner)
                buildStatusText = msg
                return
            }

            var job = try JSONDecoder().decode(TheosBuildJobResponse.self, from: postData)
            activeJobID = job.id
            var logOffset = job.logOffset ?? 0
            if let initialLog = job.log, !initialLog.isEmpty {
                appendLog(initialLog, runner: runner)
            }

            // Poll job logs & status
            while !Task.isCancelled && (job.state == "queued" || job.state == "running") {
                if job.state == "queued" {
                    let pos = job.position ?? 1
                    buildStatusText = "Đang xếp hàng vị trí #\(pos)..."
                } else {
                    buildStatusText = "Đang biên dịch Theos (.deb / .dylib)..."
                }

                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }

                var comps = URLComponents(url: baseURL.appendingPathComponent("v1/builds/\(job.id)"), resolvingAgainstBaseURL: false)
                comps?.queryItems = [URLQueryItem(name: "since", value: "\(logOffset)")]
                guard let pollURL = comps?.url else { break }

                var pollReq = URLRequest(url: pollURL)
                pollReq.timeoutInterval = 20
                let (pollData, pollResp) = try await URLSession.shared.data(for: pollReq)
                if let pHttp = pollResp as? HTTPURLResponse, pHttp.statusCode == 404 {
                    appendLog("\n[3012] Phiên build đã hết hạn trên máy chủ.\n", runner: runner)
                    buildStatusText = "Build hết hạn"
                    return
                }
                job = try JSONDecoder().decode(TheosBuildJobResponse.self, from: pollData)
                if let nextOff = job.logOffset {
                    logOffset = nextOff
                }
                if let chunk = job.log, !chunk.isEmpty {
                    appendLog(chunk, runner: runner)
                }
            }

            if Task.isCancelled { return }

            if job.state == "succeeded", let files = job.files, !files.isEmpty {
                buildStatusText = "Đang tải \(files.count) file kết quả về máy..."
                let packagesDir = workspaceRoot.appendingPathComponent("packages", isDirectory: true)
                try? FileManager.default.createDirectory(at: packagesDir, withIntermediateDirectories: true)

                var savedNames: [String] = []
                for f in files {
                    var dlReq = URLRequest(url: baseURL.appendingPathComponent("v1/builds/\(job.id)/files/\(f.name)"))
                    dlReq.timeoutInterval = 60
                    dlReq.setValue(deviceID, forHTTPHeaderField: "X-Device-ID")
                    let (binData, dlResp) = try await URLSession.shared.data(for: dlReq)
                    if let dHttp = dlResp as? HTTPURLResponse, dHttp.statusCode == 200 {
                        let outURL = packagesDir.appendingPathComponent(f.name)
                        try binData.write(to: outURL, options: .atomic)
                        savedNames.append(f.name)
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

    // MARK: - Mode 2: Private SSH VPS Build
    private func buildViaPrivateSSHVPS(
        workspaceRoot: URL,
        sshService: SSHWorkspaceService,
        runner: CodeRunnerService,
        onWorkspaceChanged: @escaping () -> Void
    ) async {
        guard sshService.isConnected else {
            appendLog("[3012] Chưa kết nối SSH VPS. Hãy mở tab Remote SSH bên trái để đăng nhập VPS trước.\n", runner: runner)
            buildStatusText = "Chưa kết nối SSH VPS"
            return
        }
        guard let zipData = createCleanTheosZipData(workspaceRoot: workspaceRoot) else {
            appendLog("[3012] Không thể nén dự án Theos.\n", runner: runner)
            buildStatusText = "Lỗi nén .zip"
            return
        }

        let remoteDir = "/tmp/3012_theos_\(String(UUID().uuidString.prefix(8)))"
        let b64Zip = zipData.base64EncodedString()
        let schemeArg = packageScheme == .rootful ? "" : "THEOS_PACKAGE_SCHEME=\(packageScheme.rawValue)"

        buildStatusText = "Đang đẩy mã nguồn & biên dịch trên VPS..."
        appendLog("[3012] Đang biên dịch qua SSH trên VPS (\(sshService.connectedProfile?.host ?? "VPS"))...\n", runner: runner)

        let buildScript = """
        rm -rf '\(remoteDir)' && mkdir -p '\(remoteDir)/src' && cd '\(remoteDir)' && \
        cat <<'EOF_ZIP' | base64 -d > proj.zip
        \(b64Zip)
        EOF_ZIP
        unzip -qq -o proj.zip -d src && \
        PROJ=$(find src -maxdepth 4 -type f -name Makefile | head -n 1 | xargs -r dirname) && \
        cd "$PROJ" && \
        make -j2 package FINALPACKAGE=1 \(schemeArg) 2>&1; echo "__3012_EXIT=$?"
        """
        let vpsOutput = await sshService.executeCommandOnVPS(buildScript)
        appendLog(vpsOutput + "\n", runner: runner)

        let listOut = await sshService.executeCommandOnVPS(
            "find '\(remoteDir)/src' -type f \\( -name '*.deb' -o -name '*.dylib' \\) -print"
        )
        let remoteArtifacts = listOut
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix(remoteDir) && ($0.hasSuffix(".deb") || $0.hasSuffix(".dylib")) }

        if remoteArtifacts.isEmpty {
            _ = await sshService.executeCommandOnVPS("rm -rf '\(remoteDir)'")
            buildStatusText = "Build SSH thất bại hoặc chưa có Theos trên VPS"
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

        guard let zipData = createCleanTheosZipData(workspaceRoot: workspaceRoot) else {
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
    public func syncMakefileSourceFiles(in workspace: WorkspaceManager, isEnglish: Bool = false) -> String {
        let fm = FileManager.default
        let rootURL = workspace.rootURL.standardizedFileURL
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
        let rootPath = rootURL.path

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

                let stdPath = url.standardizedFileURL.path
                var relPath = stdPath
                if relPath.hasPrefix(rootPath) {
                    relPath = String(relPath.dropFirst(rootPath.count))
                }
                relPath = relPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
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

        var lines = rawContent.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")

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
                if lhs == filesKey || (existingFilesPrefix != nil && lhs == "\(existingFilesPrefix!)_FILES") {
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

        let updatedContent = newLines.joined(separator: "\n")
        do {
            try updatedContent.write(to: targetURL, atomically: true, encoding: .utf8)
            workspace.reloadTree()
            if let tabIdx = workspace.openTabs.firstIndex(where: { $0.fileURL.standardizedFileURL == targetURL.standardizedFileURL }) {
                workspace.openTabs[tabIdx].content = updatedContent
                workspace.openTabs[tabIdx].savedContent = updatedContent
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
        if raw.isEmpty { raw = Self.defaultServerURL }
        if !raw.hasPrefix("http://") && !raw.hasPrefix("https://") {
            raw = "https://" + raw
        }
        while raw.hasSuffix("/") { raw.removeLast() }
        return URL(string: raw)
    }

    private func createCleanTheosZipData(workspaceRoot: URL) -> Data? {
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
            let excludedDirs: Set<String> = [".git", ".theos", "packages", ".build", "node_modules", "__MACOSX"]
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
