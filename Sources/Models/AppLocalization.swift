import Foundation
import SwiftUI
import UIKit

public enum IDEAuthorInfo {
    public static let fullName = "Le The Khoi"
    public static let countryVietnamese = "Việt Nam"
    public static let countryEnglish = "Vietnam"
    public static let telegramHandle = "@coder_009"
    public static let telegramURL = URL(string: "https://t.me/coder_009")!
    public static let githubHandle = "@userlethekhoi"
    public static let githubRepoURL = URL(string: "https://github.com/userlethekhoi/3012")!
    public static let licenseName = "GNU AGPLv3"
}

public enum AppLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case vietnamese = "vi"
    case english = "en"
    case chineseSimplified = "zh-Hans"
    case japanese = "ja"
    case korean = "ko"
    case russian = "ru"
    case spanish = "es"

    public static let storageKey = "3012.appLanguage"

    private static let lock = NSLock()
    private static var _cachedCurrent: AppLanguage = {
        if let saved = UserDefaults.standard.string(forKey: storageKey),
           let parsed = AppLanguage(rawValue: saved) {
            return parsed
        }
        return .vietnamese
    }()

    public static var current: AppLanguage {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _cachedCurrent
        }
        set {
            lock.lock()
            _cachedCurrent = newValue
            lock.unlock()
            UserDefaults.standard.set(newValue.rawValue, forKey: storageKey)
        }
    }

    public var id: String { rawValue }

    public var shortBadge: String {
        switch self {
        case .vietnamese: return "VI"
        case .english: return "EN"
        case .chineseSimplified: return "ZH"
        case .japanese: return "JA"
        case .korean: return "KO"
        case .russian: return "RU"
        case .spanish: return "ES"
        }
    }

    public var nativeName: String {
        switch self {
        case .vietnamese: return "Tiếng Việt"
        case .english: return "English"
        case .chineseSimplified: return "中文 (简体)"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .russian: return "Русский"
        case .spanish: return "Español"
        }
    }

    public var localeIdentifier: String {
        switch self {
        case .vietnamese: return "vi_VN"
        case .english: return "en_US"
        case .chineseSimplified: return "zh_Hans_CN"
        case .japanese: return "ja_JP"
        case .korean: return "ko_KR"
        case .russian: return "ru_RU"
        case .spanish: return "es_ES"
        }
    }

    public func displayName(in viewer: AppLanguage) -> String {
        if self == .vietnamese {
            switch viewer {
            case .vietnamese: return "Tiếng Việt (Mặc định)"
            case .english: return "Tiếng Việt (Default)"
            case .chineseSimplified: return "Tiếng Việt (默认)"
            case .japanese: return "Tiếng Việt (デフォルト)"
            case .korean: return "Tiếng Việt (기본값)"
            case .russian: return "Tiếng Việt (По умолчанию)"
            case .spanish: return "Tiếng Việt (Predeterminado)"
            }
        }
        return nativeName
    }

    public func tr(
        _ vi: String,
        _ en: String,
        zh: String? = nil,
        ja: String? = nil,
        ko: String? = nil,
        ru: String? = nil,
        es: String? = nil
    ) -> String {
        switch self {
        case .vietnamese: return vi
        case .english: return en
        case .chineseSimplified: return zh ?? en
        case .japanese: return ja ?? en
        case .korean: return ko ?? en
        case .russian: return ru ?? en
        case .spanish: return es ?? en
        }
    }
}

public enum L10n {
    public static func tr(
        _ vi: String,
        _ en: String,
        zh: String? = nil,
        ja: String? = nil,
        ko: String? = nil,
        ru: String? = nil,
        es: String? = nil
    ) -> String {
        AppLanguage.current.tr(vi, en, zh: zh, ja: ja, ko: ko, ru: ru, es: es)
    }
}

public struct CompatibleNavigationContainer<Content: View>: View {
    private let content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack {
                content()
            }
        } else {
            NavigationView {
                content()
            }
            .navigationViewStyle(.stack)
        }
    }
}

public struct CompatibleFileShareButton<LabelContent: View>: View {
    private let item: URL
    private let label: () -> LabelContent

    public init(item: URL, @ViewBuilder label: @escaping () -> LabelContent) {
        self.item = item
        self.label = label
    }

    public var body: some View {
        if #available(iOS 16.0, *) {
            ShareLink(item: item, label: label)
        } else {
            Button {
                Self.presentActivitySheet(for: item)
            } label: {
                label()
            }
        }
    }

    @MainActor
    private static func presentActivitySheet(for url: URL) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController ?? scene.windows.first?.rootViewController else {
            return
        }
        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let pop = activity.popoverPresentationController {
            pop.sourceView = topVC.view
            pop.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 1, height: 1)
            pop.permittedArrowDirections = []
        }
        topVC.present(activity, animated: true)
    }
}
