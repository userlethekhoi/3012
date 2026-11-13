import Foundation
import SwiftUI
import UIKit
import Runestone

public struct IDEColorPalette: Codable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var isDark: Bool
    public var editorBackground: String
    public var sidebarBackground: String
    public var headerBackground: String
    public var foreground: String
    public var gutterForeground: String
    public var currentLineBackground: String
    public var selectionBackground: String
    public var accent: String

    // Syntax Tokens
    public var comment: String
    public var keyword: String
    public var string: String
    public var number: String
    public var function: String
    public var typeName: String
    public var variable: String
    public var property: String
    public var operatorToken: String
    public var tag: String

    public init(
        id: String,
        name: String,
        isDark: Bool,
        editorBackground: String,
        sidebarBackground: String,
        headerBackground: String,
        foreground: String,
        gutterForeground: String,
        currentLineBackground: String,
        selectionBackground: String,
        accent: String,
        comment: String,
        keyword: String,
        string: String,
        number: String,
        function: String,
        typeName: String,
        variable: String,
        property: String,
        operatorToken: String,
        tag: String
    ) {
        self.id = id
        self.name = name
        self.isDark = isDark
        self.editorBackground = editorBackground
        self.sidebarBackground = sidebarBackground
        self.headerBackground = headerBackground
        self.foreground = foreground
        self.gutterForeground = gutterForeground
        self.currentLineBackground = currentLineBackground
        self.selectionBackground = selectionBackground
        self.accent = accent
        self.comment = comment
        self.keyword = keyword
        self.string = string
        self.number = number
        self.function = function
        self.typeName = typeName
        self.variable = variable
        self.property = property
        self.operatorToken = operatorToken
        self.tag = tag
    }

    public static let builtInThemes: [IDEColorPalette] = [
        IDEColorPalette(
            id: "tokyo-night",
            name: "Tokyo Night",
            isDark: true,
            editorBackground: "#1A1B26",
            sidebarBackground: "#16161E",
            headerBackground: "#13141C",
            foreground: "#C0CAF5",
            gutterForeground: "#565F89",
            currentLineBackground: "#24283B",
            selectionBackground: "#33467C",
            accent: "#7AA2F7",
            comment: "#565F89",
            keyword: "#BB9AF7",
            string: "#9ECE6A",
            number: "#FF9E64",
            function: "#7AA2F7",
            typeName: "#2AC3DE",
            variable: "#F7768E",
            property: "#7DCFFF",
            operatorToken: "#89DDFF",
            tag: "#F7768E"
        ),
        IDEColorPalette(
            id: "cursor-dark",
            name: "Cursor Midnight",
            isDark: true,
            editorBackground: "#141414",
            sidebarBackground: "#101010",
            headerBackground: "#0C0C0C",
            foreground: "#E4E4E7",
            gutterForeground: "#52525B",
            currentLineBackground: "#1E1E22",
            selectionBackground: "#2563EB",
            accent: "#3B82F6",
            comment: "#6B7280",
            keyword: "#C084FC",
            string: "#86EFAC",
            number: "#FDBA74",
            function: "#60A5FA",
            typeName: "#38BDF8",
            variable: "#F87171",
            property: "#93C5FD",
            operatorToken: "#67E8F9",
            tag: "#FB7185"
        ),
        IDEColorPalette(
            id: "xcode-dark",
            name: "Xcode Default Dark",
            isDark: true,
            editorBackground: "#1F1F24",
            sidebarBackground: "#1A1A1E",
            headerBackground: "#151518",
            foreground: "#FFFFFF",
            gutterForeground: "#74747C",
            currentLineBackground: "#26262C",
            selectionBackground: "#2E4C7D",
            accent: "#0A84FF",
            comment: "#6C7986",
            keyword: "#FC5FA3",
            string: "#FC6A5D",
            number: "#D0BF69",
            function: "#67B7A4",
            typeName: "#D0A8FF",
            variable: "#41A1C0",
            property: "#9EF1DD",
            operatorToken: "#FFFFFF",
            tag: "#FC5FA3"
        ),
        IDEColorPalette(
            id: "one-dark-pro",
            name: "One Dark Pro",
            isDark: true,
            editorBackground: "#282C34",
            sidebarBackground: "#21252B",
            headerBackground: "#1E2227",
            foreground: "#ABB2BF",
            gutterForeground: "#636D83",
            currentLineBackground: "#2C313C",
            selectionBackground: "#3E4451",
            accent: "#61AFEF",
            comment: "#5C6370",
            keyword: "#C678DD",
            string: "#98C379",
            number: "#D19A66",
            function: "#61AFEF",
            typeName: "#E5C07B",
            variable: "#E06C75",
            property: "#56B6C2",
            operatorToken: "#56B6C2",
            tag: "#E06C75"
        ),
        IDEColorPalette(
            id: "dracula",
            name: "Dracula",
            isDark: true,
            editorBackground: "#282A36",
            sidebarBackground: "#21222C",
            headerBackground: "#191A21",
            foreground: "#F8F8F2",
            gutterForeground: "#6272A4",
            currentLineBackground: "#44475A",
            selectionBackground: "#44475A",
            accent: "#BD93F9",
            comment: "#6272A4",
            keyword: "#FF79C6",
            string: "#F1FA8C",
            number: "#BD93F9",
            function: "#50FA7B",
            typeName: "#8BE9FD",
            variable: "#FFB86C",
            property: "#8BE9FD",
            operatorToken: "#FF79C6",
            tag: "#FF79C6"
        ),
        IDEColorPalette(
            id: "catppuccin-mocha",
            name: "Catppuccin Mocha",
            isDark: true,
            editorBackground: "#1E1E2E",
            sidebarBackground: "#181825",
            headerBackground: "#11111B",
            foreground: "#CDD6F4",
            gutterForeground: "#6C7086",
            currentLineBackground: "#313244",
            selectionBackground: "#45475A",
            accent: "#89B4FA",
            comment: "#6C7086",
            keyword: "#CBA6F7",
            string: "#A6E3A1",
            number: "#FAB387",
            function: "#89B4FA",
            typeName: "#F9E2AF",
            variable: "#F38BA8",
            property: "#94E2D5",
            operatorToken: "#89DCEB",
            tag: "#F38BA8"
        ),
        IDEColorPalette(
            id: "monokai-pro",
            name: "Monokai Pro",
            isDark: true,
            editorBackground: "#2D2A2E",
            sidebarBackground: "#221F22",
            headerBackground: "#19181A",
            foreground: "#FCFCFA",
            gutterForeground: "#727072",
            currentLineBackground: "#383539",
            selectionBackground: "#5B595C",
            accent: "#FFD866",
            comment: "#727072",
            keyword: "#FF6188",
            string: "#FFD866",
            number: "#AB9DF2",
            function: "#A9DC76",
            typeName: "#78DCE8",
            variable: "#FC9867",
            property: "#78DCE8",
            operatorToken: "#FF6188",
            tag: "#FF6188"
        ),
        IDEColorPalette(
            id: "github-dark",
            name: "GitHub Dark",
            isDark: true,
            editorBackground: "#0D1117",
            sidebarBackground: "#010409",
            headerBackground: "#010409",
            foreground: "#E6EDF3",
            gutterForeground: "#6E7681",
            currentLineBackground: "#161B22",
            selectionBackground: "#1F6FEB",
            accent: "#2F81F7",
            comment: "#8B949E",
            keyword: "#FF7B72",
            string: "#A5D6FF",
            number: "#79C0FF",
            function: "#D2A8FF",
            typeName: "#FFA657",
            variable: "#FFA657",
            property: "#79C0FF",
            operatorToken: "#FF7B72",
            tag: "#7EE787"
        ),
        IDEColorPalette(
            id: "nord",
            name: "Nord",
            isDark: true,
            editorBackground: "#2E3440",
            sidebarBackground: "#272C36",
            headerBackground: "#232831",
            foreground: "#D8DEE9",
            gutterForeground: "#616E88",
            currentLineBackground: "#3B4252",
            selectionBackground: "#434C5E",
            accent: "#88C0D0",
            comment: "#616E88",
            keyword: "#81A1C1",
            string: "#A3BE8C",
            number: "#B48EAD",
            function: "#88C0D0",
            typeName: "#8FBCBB",
            variable: "#D8DEE9",
            property: "#8FBCBB",
            operatorToken: "#81A1C1",
            tag: "#81A1C1"
        ),
        IDEColorPalette(
            id: "gruvbox-dark",
            name: "Gruvbox Dark",
            isDark: true,
            editorBackground: "#282828",
            sidebarBackground: "#1D2021",
            headerBackground: "#191B1C",
            foreground: "#EBDBB2",
            gutterForeground: "#7C6F64",
            currentLineBackground: "#3C3836",
            selectionBackground: "#504945",
            accent: "#FE8019",
            comment: "#928374",
            keyword: "#FB4934",
            string: "#B8BB26",
            number: "#D3869B",
            function: "#FABD2F",
            typeName: "#8EC07C",
            variable: "#83A598",
            property: "#8EC07C",
            operatorToken: "#FE8019",
            tag: "#FB4934"
        ),
        IDEColorPalette(
            id: "solarized-dark",
            name: "Solarized Dark",
            isDark: true,
            editorBackground: "#002B36",
            sidebarBackground: "#073642",
            headerBackground: "#00212B",
            foreground: "#839496",
            gutterForeground: "#586E75",
            currentLineBackground: "#073642",
            selectionBackground: "#174A5A",
            accent: "#268BD2",
            comment: "#586E75",
            keyword: "#859900",
            string: "#2AA198",
            number: "#D33682",
            function: "#268BD2",
            typeName: "#B58900",
            variable: "#CB4B16",
            property: "#268BD2",
            operatorToken: "#859900",
            tag: "#268BD2"
        ),
        IDEColorPalette(
            id: "xcode-light",
            name: "Xcode Default Light",
            isDark: false,
            editorBackground: "#FFFFFF",
            sidebarBackground: "#F4F5F7",
            headerBackground: "#ECEEF1",
            foreground: "#000000",
            gutterForeground: "#8E8E93",
            currentLineBackground: "#F2F6FC",
            selectionBackground: "#B4D8FD",
            accent: "#007AFF",
            comment: "#5D6C79",
            keyword: "#9B2393",
            string: "#C41A16",
            number: "#1C00CF",
            function: "#326D74",
            typeName: "#3900A0",
            variable: "#0F68A0",
            property: "#326D74",
            operatorToken: "#000000",
            tag: "#9B2393"
        ),
        IDEColorPalette(
            id: "github-light",
            name: "GitHub Light",
            isDark: false,
            editorBackground: "#FFFFFF",
            sidebarBackground: "#F6F8FA",
            headerBackground: "#EFF2F5",
            foreground: "#24292F",
            gutterForeground: "#8C959F",
            currentLineBackground: "#F6F8FA",
            selectionBackground: "#BBDFFF",
            accent: "#0969DA",
            comment: "#6E7781",
            keyword: "#CF222E",
            string: "#0A3069",
            number: "#0550AE",
            function: "#8250DF",
            typeName: "#953800",
            variable: "#24292F",
            property: "#0550AE",
            operatorToken: "#CF222E",
            tag: "#116329"
        ),
        IDEColorPalette(
            id: "catppuccin-latte",
            name: "Catppuccin Latte",
            isDark: false,
            editorBackground: "#EFF1F5",
            sidebarBackground: "#E6E9EF",
            headerBackground: "#DCE0E8",
            foreground: "#4C4F69",
            gutterForeground: "#8C8FA1",
            currentLineBackground: "#E6E9EF",
            selectionBackground: "#ACB0BE",
            accent: "#1E66F5",
            comment: "#8C8FA1",
            keyword: "#8839EF",
            string: "#40A02B",
            number: "#FE640B",
            function: "#1E66F5",
            typeName: "#DF8E1D",
            variable: "#D20F39",
            property: "#179299",
            operatorToken: "#04A5E5",
            tag: "#D20F39"
        )
    ]
}

public extension UIColor {
    convenience init(hexString: String) {
        var cleaned = hexString.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleaned.hasPrefix("#") {
            cleaned.removeFirst()
        }
        var rgbValue: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&rgbValue)
        switch cleaned.count {
        case 8:
            let r = CGFloat((rgbValue & 0xFF000000) >> 24) / 255.0
            let g = CGFloat((rgbValue & 0x00FF0000) >> 16) / 255.0
            let b = CGFloat((rgbValue & 0x0000FF00) >> 8) / 255.0
            let a = CGFloat(rgbValue & 0x000000FF) / 255.0
            self.init(red: r, green: g, blue: b, alpha: a)
        default:
            let r = CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0
            let g = CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0
            let b = CGFloat(rgbValue & 0x0000FF) / 255.0
            self.init(red: r, green: g, blue: b, alpha: 1.0)
        }
    }

    func toHexString() -> String {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 1
        if getRed(&r, green: &g, blue: &b, alpha: &a) {
            let ri = Int(round(min(max(r, 0), 1) * 255))
            let gi = Int(round(min(max(g, 0), 1) * 255))
            let bi = Int(round(min(max(b, 0), 1) * 255))
            return String(format: "#%02X%02X%02X", ri, gi, bi)
        }
        return "#0A84FF"
    }
}

public extension Color {
    init(hex: String) {
        self.init(uiColor: UIColor(hexString: hex))
    }

    func toHexString() -> String {
        UIColor(self).toHexString()
    }
}

public final class IDERunestoneTheme: Runestone.Theme {
    public let palette: IDEColorPalette
    public let font: UIFont
    public let lineNumberFont: UIFont

    public var textColor: UIColor { UIColor(hexString: palette.foreground) }
    public var gutterBackgroundColor: UIColor { UIColor(hexString: palette.editorBackground) }
    public var gutterHairlineColor: UIColor { UIColor(hexString: palette.currentLineBackground) }
    public var lineNumberColor: UIColor { UIColor(hexString: palette.gutterForeground) }
    public var selectedLineBackgroundColor: UIColor { UIColor(hexString: palette.currentLineBackground) }
    public var selectedLinesLineNumberColor: UIColor { UIColor(hexString: palette.foreground) }
    public var selectedLinesGutterBackgroundColor: UIColor { UIColor(hexString: palette.currentLineBackground) }
    public var invisibleCharactersColor: UIColor { UIColor(hexString: palette.gutterForeground).withAlphaComponent(0.45) }
    public var pageGuideHairlineColor: UIColor { UIColor(hexString: palette.currentLineBackground) }
    public var pageGuideBackgroundColor: UIColor { UIColor(hexString: palette.sidebarBackground) }
    public var markedTextBackgroundColor: UIColor { UIColor(hexString: palette.selectionBackground) }

    public init(palette: IDEColorPalette, fontName: String, fontSize: CGFloat) {
        self.palette = palette
        if fontName == "System Mono" {
            self.font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            self.lineNumberFont = UIFont.monospacedSystemFont(ofSize: max(10, fontSize - 2), weight: .regular)
        } else {
            self.font = UIFont(name: fontName, size: fontSize) ?? UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            self.lineNumberFont = UIFont(name: fontName, size: max(10, fontSize - 2)) ?? UIFont.monospacedSystemFont(ofSize: max(10, fontSize - 2), weight: .regular)
        }
    }

    public func textColor(for highlightName: String) -> UIColor? {
        let key = highlightName.lowercased()
        if key.hasPrefix("comment") {
            return UIColor(hexString: palette.comment)
        } else if key.hasPrefix("keyword") || key == "include" || key == "conditional" || key == "repeat" || key == "storageclass" {
            return UIColor(hexString: palette.keyword)
        } else if key.hasPrefix("string") || key == "character" {
            return UIColor(hexString: palette.string)
        } else if key.hasPrefix("number") || key.hasPrefix("boolean") || key.hasPrefix("float") || key.hasPrefix("constant.builtin") {
            return UIColor(hexString: palette.number)
        } else if key.hasPrefix("function") || key.hasPrefix("method") || key == "constructor" {
            return UIColor(hexString: palette.function)
        } else if key.hasPrefix("type") || key == "namespace" {
            return UIColor(hexString: palette.typeName)
        } else if key.hasPrefix("tag") {
            return UIColor(hexString: palette.tag)
        } else if key.hasPrefix("property") || key.hasPrefix("attribute") || key.hasPrefix("field") {
            return UIColor(hexString: palette.property)
        } else if key.hasPrefix("variable.builtin") || key.hasPrefix("parameter") || key == "variable" {
            return UIColor(hexString: palette.variable)
        } else if key.hasPrefix("operator") || key.hasPrefix("punctuation.special") {
            return UIColor(hexString: palette.operatorToken)
        } else if key.hasPrefix("constant") {
            return UIColor(hexString: palette.number)
        }
        return nil
    }

    public func fontTraits(for highlightName: String) -> FontTraits {
        if highlightName.hasPrefix("keyword") {
            return .bold
        } else if highlightName.hasPrefix("comment") {
            return .italic
        }
        return []
    }
}

public enum VSCodeThemeImporter {
    public static func parse(jsonData: Data, fallbackName: String) -> IDEColorPalette? {
        guard let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }
        let name = (root["name"] as? String) ?? fallbackName
        let typeStr = ((root["type"] as? String) ?? "dark").lowercased()
        let isDark = typeStr != "light"
        let base = isDark ? IDEColorPalette.builtInThemes[0] : IDEColorPalette.builtInThemes[11]

        let colors = (root["colors"] as? [String: String]) ?? [:]
        let editorBg = colors["editor.background"] ?? base.editorBackground
        let sidebarBg = colors["sideBar.background"] ?? editorBg
        let headerBg = colors["titleBar.activeBackground"] ?? sidebarBg
        let fg = colors["editor.foreground"] ?? base.foreground
        let gutterFg = colors["editorLineNumber.foreground"] ?? base.gutterForeground
        let lineBg = colors["editor.lineHighlightBackground"] ?? base.currentLineBackground
        let selBg = colors["editor.selectionBackground"] ?? base.selectionBackground
        let accent = colors["button.background"] ?? colors["focusBorder"] ?? base.accent

        var comment = base.comment
        var keyword = base.keyword
        var stringCol = base.string
        var number = base.number
        var function = base.function
        var typeCol = base.typeName
        var variable = base.variable
        var property = base.property
        var tag = base.tag

        if let tokenColors = root["tokenColors"] as? [[String: Any]] {
            for entry in tokenColors {
                guard let settings = entry["settings"] as? [String: Any],
                      let hex = settings["foreground"] as? String else { continue }
                let scopes: [String]
                if let single = entry["scope"] as? String {
                    scopes = single.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                } else if let arr = entry["scope"] as? [String] {
                    scopes = arr
                } else {
                    continue
                }
                for scope in scopes {
                    if scope.contains("comment") { comment = hex }
                    else if scope.contains("keyword") || scope.contains("storage") { keyword = hex }
                    else if scope.contains("string") { stringCol = hex }
                    else if scope.contains("constant.numeric") { number = hex }
                    else if scope.contains("entity.name.function") { function = hex }
                    else if scope.contains("entity.name.type") || scope.contains("support.class") { typeCol = hex }
                    else if scope.contains("entity.name.tag") { tag = hex }
                    else if scope.contains("variable.other.property") || scope.contains("support.type.property-name") { property = hex }
                    else if scope == "variable" { variable = hex }
                }
            }
        }

        return IDEColorPalette(
            id: "custom-\(UUID().uuidString.prefix(8))",
            name: name,
            isDark: isDark,
            editorBackground: editorBg,
            sidebarBackground: sidebarBg,
            headerBackground: headerBg,
            foreground: fg,
            gutterForeground: gutterFg,
            currentLineBackground: lineBg,
            selectionBackground: selBg,
            accent: accent,
            comment: comment,
            keyword: keyword,
            string: stringCol,
            number: number,
            function: function,
            typeName: typeCol,
            variable: variable,
            property: property,
            operatorToken: keyword,
            tag: tag
        )
    }
}

public final class EditorPreferences: ObservableObject {
    public static let availableFonts: [String] = [
        "System Mono",
        "Menlo-Regular",
        "CourierNewPSMT"
    ]

    public static let appAccentPresets: [(name: String, hex: String)] = [
        ("Theo Theme", ""),
        ("iOS Blue", "#0A84FF"),
        ("Cyan", "#38BDF8"),
        ("Indigo", "#6366F1"),
        ("Purple", "#A855F7"),
        ("Emerald", "#10B981"),
        ("Amber", "#F59E0B"),
        ("Rose", "#F43F5E")
    ]

    @Published public var appLanguage: AppLanguage {
        didSet {
            AppLanguage.current = appLanguage
        }
    }
    @Published public var selectedThemeID: String {
        didSet { UserDefaults.standard.set(selectedThemeID, forKey: "3012.themeID") }
    }
    @Published public var customAccentHex: String {
        didSet { UserDefaults.standard.set(customAccentHex, forKey: "3012.customAccentHex") }
    }
    @Published public var fontName: String {
        didSet { UserDefaults.standard.set(fontName, forKey: "3012.fontName") }
    }
    @Published public var fontSize: CGFloat {
        didSet {
            let clamped = min(max(fontSize, 10), 28)
            if fontSize != clamped { fontSize = clamped }
            UserDefaults.standard.set(Double(clamped), forKey: "3012.fontSize")
        }
    }
    @Published public var lineHeightMultiplier: Double {
        didSet { UserDefaults.standard.set(lineHeightMultiplier, forKey: "3012.lineHeight") }
    }
    @Published public var tabWidth: Int {
        didSet { UserDefaults.standard.set(tabWidth, forKey: "3012.tabWidth") }
    }
    @Published public var wordWrap: Bool {
        didSet { UserDefaults.standard.set(wordWrap, forKey: "3012.wordWrap") }
    }
    @Published public var showLineNumbers: Bool {
        didSet { UserDefaults.standard.set(showLineNumbers, forKey: "3012.showLineNumbers") }
    }
    @Published public var showInvisibleCharacters: Bool {
        didSet { UserDefaults.standard.set(showInvisibleCharacters, forKey: "3012.showInvisibles") }
    }
    @Published public var enableCodeFolding: Bool {
        didSet { UserDefaults.standard.set(enableCodeFolding, forKey: "3012.codeFolding") }
    }
    @Published public var enableCodeCompletion: Bool {
        didSet { UserDefaults.standard.set(enableCodeCompletion, forKey: "3012.codeCompletion") }
    }
    @Published public var enableLiveDiagnostics: Bool {
        didSet { UserDefaults.standard.set(enableLiveDiagnostics, forKey: "3012.liveDiagnostics") }
    }
    @Published public var enableAutoSave: Bool {
        didSet { UserDefaults.standard.set(enableAutoSave, forKey: "3012.autoSave") }
    }
    @Published public var formatOnSave: Bool {
        didSet { UserDefaults.standard.set(formatOnSave, forKey: "3012.formatOnSave") }
    }
    @Published public var autoIndentOnReturn: Bool {
        didSet { UserDefaults.standard.set(autoIndentOnReturn, forKey: "3012.autoIndentReturn") }
    }
    @Published public var showBreadcrumbs: Bool {
        didSet { UserDefaults.standard.set(showBreadcrumbs, forKey: "3012.showBreadcrumbs") }
    }
    @Published public var keepServerInBackground: Bool {
        didSet { UserDefaults.standard.set(keepServerInBackground, forKey: "3012.keepServerBg") }
    }
    @Published public var customThemes: [IDEColorPalette] = [] {
        didSet { saveCustomThemes() }
    }

    public var allThemes: [IDEColorPalette] {
        IDEColorPalette.builtInThemes + customThemes
    }

    public var activePalette: IDEColorPalette {
        var base = allThemes.first(where: { $0.id == selectedThemeID }) ?? IDEColorPalette.builtInThemes[0]
        if !customAccentHex.isEmpty {
            base.accent = customAccentHex
        }
        return base
    }

    /// Returns a checksum string covering custom theme colors so Runestone refreshes immediately on live color edits.
    public var themeSignature: String {
        let p = activePalette
        return "\(p.id)|\(p.editorBackground)|\(p.foreground)|\(p.accent)|\(p.keyword)|\(p.string)|\(p.function)|\(p.typeName)|\(p.number)|\(p.comment)|\(p.variable)|\(p.tag)"
    }

    public init() {
        let savedLang = UserDefaults.standard.string(forKey: AppLanguage.storageKey)
            .flatMap(AppLanguage.init(rawValue:)) ?? .vietnamese
        self.appLanguage = savedLang
        AppLanguage.current = savedLang
        self.selectedThemeID = UserDefaults.standard.string(forKey: "3012.themeID") ?? "tokyo-night"
        self.customAccentHex = UserDefaults.standard.string(forKey: "3012.customAccentHex") ?? ""
        self.fontName = UserDefaults.standard.string(forKey: "3012.fontName") ?? "Menlo-Regular"
        let savedSize = UserDefaults.standard.double(forKey: "3012.fontSize")
        self.fontSize = savedSize > 0 ? CGFloat(savedSize) : 14.0
        let savedLH = UserDefaults.standard.double(forKey: "3012.lineHeight")
        self.lineHeightMultiplier = savedLH > 0 ? savedLH : 1.22
        let savedTab = UserDefaults.standard.integer(forKey: "3012.tabWidth")
        self.tabWidth = savedTab > 0 ? savedTab : 2
        self.wordWrap = UserDefaults.standard.object(forKey: "3012.wordWrap") as? Bool ?? true
        self.showLineNumbers = UserDefaults.standard.object(forKey: "3012.showLineNumbers") as? Bool ?? true
        self.showInvisibleCharacters = UserDefaults.standard.object(forKey: "3012.showInvisibles") as? Bool ?? false
        self.enableCodeFolding = UserDefaults.standard.object(forKey: "3012.codeFolding") as? Bool ?? true
        self.enableCodeCompletion = UserDefaults.standard.object(forKey: "3012.codeCompletion") as? Bool ?? true
        self.enableLiveDiagnostics = UserDefaults.standard.object(forKey: "3012.liveDiagnostics") as? Bool ?? true
        self.enableAutoSave = UserDefaults.standard.object(forKey: "3012.autoSave") as? Bool ?? true
        self.formatOnSave = UserDefaults.standard.object(forKey: "3012.formatOnSave") as? Bool ?? true
        self.autoIndentOnReturn = UserDefaults.standard.object(forKey: "3012.autoIndentReturn") as? Bool ?? true
        self.showBreadcrumbs = UserDefaults.standard.object(forKey: "3012.showBreadcrumbs") as? Bool ?? true
        self.keepServerInBackground = UserDefaults.standard.object(forKey: "3012.keepServerBg") as? Bool ?? true
        loadCustomThemes()
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
        appLanguage.tr(vi, en, zh: zh, ja: ja, ko: ko, ru: ru, es: es)
    }

    public func makeRunestoneTheme() -> IDERunestoneTheme {
        IDERunestoneTheme(palette: activePalette, fontName: fontName, fontSize: fontSize)
    }

    public func upsertCustomTheme(_ palette: IDEColorPalette) {
        if let idx = customThemes.firstIndex(where: { $0.id == palette.id }) {
            customThemes[idx] = palette
        } else {
            customThemes.append(palette)
        }
        selectedThemeID = palette.id
    }

    private func saveCustomThemes() {
        if let data = try? JSONEncoder().encode(customThemes) {
            UserDefaults.standard.set(data, forKey: "3012.customThemes")
        }
    }

    private func loadCustomThemes() {
        if let data = UserDefaults.standard.data(forKey: "3012.customThemes"),
           let decoded = try? JSONDecoder().decode([IDEColorPalette].self, from: data) {
            self.customThemes = decoded
        }
    }
}
