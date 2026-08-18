import Foundation

enum AppLocalization {
    static var localeIdentifier: String {
        UserDefaults.standard.string(forKey: "app.language") ?? "system"
    }

    static var locale: Locale {
        localeIdentifier == "system" ? .autoupdatingCurrent : Locale(identifier: localeIdentifier)
    }

    static func text(_ key: String, fallback: String) -> String {
        let language = localeIdentifier
        let bundle: Bundle
        if language != "system",
           let path = Bundle.main.path(forResource: language, ofType: "lproj"),
           let localizedBundle = Bundle(path: path) {
            bundle = localizedBundle
        } else {
            bundle = .main
        }
        return bundle.localizedString(forKey: key, value: fallback, table: "Localizable")
    }

    static func format(_ key: String, fallback: String, _ arguments: CVarArg...) -> String {
        String(format: text(key, fallback: fallback), locale: locale, arguments: arguments)
    }
}
