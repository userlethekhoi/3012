import SwiftUI

/// Pure SVG-geometry vector brand mark (`</>`) matching the iOS Home Screen AppIcon.
public struct IDECodeMarkVector: View {
    public var size: CGFloat = 18
    public var primaryColor: Color = Color(red: 0.04, green: 0.52, blue: 1.0)
    public var slashColor: Color = Color(red: 0.39, green: 0.82, blue: 1.0)
    public var secondaryColor: Color = .primary

    public init(
        size: CGFloat = 18,
        primaryColor: Color = Color(red: 0.04, green: 0.52, blue: 1.0),
        slashColor: Color = Color(red: 0.39, green: 0.82, blue: 1.0),
        secondaryColor: Color = .primary
    ) {
        self.size = size
        self.primaryColor = primaryColor
        self.slashColor = slashColor
        self.secondaryColor = secondaryColor
    }

    public var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let stroke = max(1.6, min(w, h) * 0.105)
            let style = StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round)

            var leftPath = Path()
            leftPath.move(to: CGPoint(x: w * 0.35, y: h * 0.28))
            leftPath.addLine(to: CGPoint(x: w * 0.14, y: h * 0.50))
            leftPath.addLine(to: CGPoint(x: w * 0.35, y: h * 0.72))
            context.stroke(leftPath, with: .color(primaryColor), style: style)

            var slashPath = Path()
            slashPath.move(to: CGPoint(x: w * 0.56, y: h * 0.22))
            slashPath.addLine(to: CGPoint(x: w * 0.44, y: h * 0.78))
            context.stroke(
                slashPath,
                with: .color(slashColor),
                style: StrokeStyle(lineWidth: stroke * 0.9, lineCap: .round)
            )

            var rightPath = Path()
            rightPath.move(to: CGPoint(x: w * 0.65, y: h * 0.28))
            rightPath.addLine(to: CGPoint(x: w * 0.86, y: h * 0.50))
            rightPath.addLine(to: CGPoint(x: w * 0.65, y: h * 0.72))
            context.stroke(rightPath, with: .color(secondaryColor), style: style)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Clean Apple SF Symbol + VS Code semantic color icon for all 64 languages (no emojis, no noisy fills).
public struct FileLanguageIconView: View {
    public let language: CodeLanguage
    public var size: CGFloat = 12

    public init(language: CodeLanguage, size: CGFloat = 12) {
        self.language = language
        self.size = size
    }

    public var body: some View {
        Image(systemName: language.systemIcon)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: size, weight: .medium))
            .foregroundColor(semanticColor(for: language))
            .frame(width: size + 4, height: size + 4)
    }

    private func semanticColor(for lang: CodeLanguage) -> Color {
        switch lang {
        case .html, .svelte, .astro:
            return Color(red: 0.94, green: 0.40, blue: 0.18) // Coral Orange
        case .vue:
            return Color(red: 0.26, green: 0.72, blue: 0.51) // Vue Emerald
        case .css:
            return Color(red: 0.22, green: 0.74, blue: 0.97) // Sky Blue
        case .scss, .graphql:
            return Color(red: 0.90, green: 0.33, blue: 0.60) // Pink Magenta
        case .javascript:
            return Color(red: 0.96, green: 0.78, blue: 0.18) // JS Gold
        case .typescript, .tsx:
            return Color(red: 0.23, green: 0.51, blue: 0.96) // TS Blue
        case .json, .json5, .yaml, .toml, .ini, .protobuf:
            return Color(red: 0.96, green: 0.62, blue: 0.04) // Config Amber
        case .python, .lua, .r:
            return Color(red: 0.35, green: 0.65, blue: 0.98) // Scripting Blue
        case .c, .cpp, .objectiveC, .assembly:
            return Color(red: 0.42, green: 0.50, blue: 0.96) // Systems Indigo
        case .rust, .dlang:
            return Color(red: 0.92, green: 0.46, blue: 0.24) // Rust Copper
        case .go, .dart, .dockerfile:
            return Color(red: 0.00, green: 0.74, blue: 0.88) // Cyan
        case .zig, .nim:
            return Color(red: 0.96, green: 0.68, blue: 0.16) // Warm Gold
        case .swift:
            return Color(red: 0.97, green: 0.45, blue: 0.15) // Swift Orange
        case .java, .scala:
            return Color(red: 0.93, green: 0.35, blue: 0.30) // JVM Red
        case .kotlin, .elixir, .haskell, .hcl, .bicep:
            return Color(red: 0.66, green: 0.42, blue: 0.96) // Violet
        case .csharp, .php:
            return Color(red: 0.54, green: 0.48, blue: 0.92) // Indigo Purple
        case .ruby, .erlang, .crystal:
            return Color(red: 0.88, green: 0.25, blue: 0.33) // Ruby Crimson
        case .sql:
            return Color(red: 0.24, green: 0.70, blue: 0.90) // DB Cyan
        case .shell, .fish, .powershell, .makefile, .cmake, .nix:
            return Color(red: 0.20, green: 0.83, blue: 0.60) // Terminal Emerald
        case .markdown, .latex, .xml, .diff, .regex:
            return Color(red: 0.58, green: 0.64, blue: 0.72) // Slate
        default:
            return Color.secondary
        }
    }
}
