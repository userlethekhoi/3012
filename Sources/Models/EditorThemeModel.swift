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

    public static let builtInThemes: [IDEColorPalette] = [
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
}

public extension Color {
    init(hex: String) {
        self.init(uiColor: UIColor(hexString: hex))
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
    public var invisibleCharactersColor: UIColor { UIColor(hexString: palette.gutterForeground).withAlphaComponent(0.4) }
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
        } else if key.hasPrefix("variable.builtin") || key.hasPrefix("parameter") {
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
        let base = isDark ? IDEColorPalette.builtInThemes[0] : IDEColorPalette.builtInThemes[4]

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

    @Published public var selectedThemeID: String {
        didSet { UserDefaults.standard.set(selectedThemeID, forKey: "3012.themeID") }
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
    @Published public var tabWidth: Int {
        didSet { UserDefaults.standard.set(tabWidth, forKey: "3012.tabWidth") }
    }
    @Published public var wordWrap: Bool {
        didSet { UserDefaults.standard.set(wordWrap, forKey: "3012.wordWrap") }
    }
    @Published public var showLineNumbers: Bool {
        didSet { UserDefaults.standard.set(showLineNumbers, forKey: "3012.showLineNumbers") }
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
        allThemes.first(where: { $0.id == selectedThemeID }) ?? IDEColorPalette.builtInThemes[0]
    }

    public init() {
        self.selectedThemeID = UserDefaults.standard.string(forKey: "3012.themeID") ?? "tokyo-night"
        self.fontName = UserDefaults.standard.string(forKey: "3012.fontName") ?? "Menlo-Regular"
        let savedSize = UserDefaults.standard.double(forKey: "3012.fontSize")
        self.fontSize = savedSize > 0 ? CGFloat(savedSize) : 14.0
        let savedTab = UserDefaults.standard.integer(forKey: "3012.tabWidth")
        self.tabWidth = savedTab > 0 ? savedTab : 2
        self.wordWrap = UserDefaults.standard.object(forKey: "3012.wordWrap") as? Bool ?? true
        self.showLineNumbers = UserDefaults.standard.object(forKey: "3012.showLineNumbers") as? Bool ?? true
        self.keepServerInBackground = UserDefaults.standard.object(forKey: "3012.keepServerBg") as? Bool ?? true
        loadCustomThemes()
    }

    public func makeRunestoneTheme() -> IDERunestoneTheme {
        IDERunestoneTheme(palette: activePalette, fontName: fontName, fontSize: fontSize)
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
