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

/// Clean Apple SF Symbol + VS Code semantic color icon for files and tabs (no emojis, no noisy fills).
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
        case .html:
            return Color(red: 0.94, green: 0.40, blue: 0.18) // HTML5 Coral
        case .css:
            return Color(red: 0.22, green: 0.74, blue: 0.97) // CSS Sky Blue
        case .javascript:
            return Color(red: 0.96, green: 0.78, blue: 0.18) // JS Gold
        case .typescript:
            return Color(red: 0.23, green: 0.51, blue: 0.96) // TS Blue
        case .json:
            return Color(red: 0.96, green: 0.62, blue: 0.04) // JSON Amber
        case .python:
            return Color(red: 0.35, green: 0.65, blue: 0.98) // Python Blue
        case .c:
            return Color(red: 0.45, green: 0.56, blue: 0.96) // C Slate Blue
        case .cpp:
            return Color(red: 0.39, green: 0.46, blue: 0.95) // C++ Indigo
        case .objectiveC:
            return Color(red: 0.26, green: 0.62, blue: 0.98) // Obj-C Blue
        case .swift:
            return Color(red: 0.97, green: 0.45, blue: 0.15) // Apple Swift Orange
        case .markdown:
            return Color(red: 0.58, green: 0.64, blue: 0.72) // Markdown Slate
        case .shell:
            return Color(red: 0.20, green: 0.83, blue: 0.60) // Shell Emerald
        case .plainText:
            return Color.secondary
        }
    }
}
