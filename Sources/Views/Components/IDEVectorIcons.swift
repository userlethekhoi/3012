import SwiftUI

/// Bespoke 120Hz vector brand mark (`30` / `12` with Programmer's Slashed Zero & Active Gutter Rail)
/// matching the iOS Home Screen AppIcon on an exact 1024-unit architectural grid.
public struct IDECodeMarkVector: View {
    public var size: CGFloat = 22
    public var primaryColor: Color = Color(red: 16 / 255, green: 185 / 255, blue: 129 / 255) // #10B981 Terminal Emerald
    public var slashColor: Color = Color(red: 16 / 255, green: 185 / 255, blue: 129 / 255)
    public var secondaryColor: Color = Color(red: 241 / 255, green: 245 / 255, blue: 249 / 255) // #F1F5F9 Titanium Chalk
    public var showTileBackground: Bool = true

    public init(
        size: CGFloat = 22,
        primaryColor: Color = Color(red: 16 / 255, green: 185 / 255, blue: 129 / 255),
        slashColor: Color = Color(red: 16 / 255, green: 185 / 255, blue: 129 / 255),
        secondaryColor: Color = Color(red: 241 / 255, green: 245 / 255, blue: 249 / 255),
        showTileBackground: Bool = true
    ) {
        self.size = size
        self.primaryColor = primaryColor
        self.slashColor = slashColor
        self.secondaryColor = secondaryColor
        self.showTileBackground = showTileBackground
    }

    public var body: some View {
        Canvas { context, canvasSize in
            let side = min(canvasSize.width, canvasSize.height)
            let u = side / 1024.0
            let tileRect = CGRect(x: 0, y: 0, width: side, height: side)
            let pt = { (x: CGFloat, y: CGFloat) in CGPoint(x: x * u, y: y * u) }

            var drawCtx = context
            if showTileBackground {
                let squircle = RoundedRectangle(cornerRadius: 228 * u, style: .continuous).path(in: tileRect)
                drawCtx.clip(to: squircle)

                let bgTop = Color(red: 20 / 255, green: 26 / 255, blue: 34 / 255) // #141A22 Anodized Carbon
                let bgBot = Color(red: 10 / 255, green: 13 / 255, blue: 18 / 255) // #0A0D12 Deep Obsidian
                drawCtx.fill(
                    squircle,
                    with: .linearGradient(
                        Gradient(colors: [bgTop, bgBot]),
                        startPoint: CGPoint(x: side * 0.5, y: 0),
                        endPoint: CGPoint(x: side * 0.5, y: side)
                    )
                )

                // Subtle 128-unit blueprint grid & registration ticks at medium/large display sizes
                if size >= 36 {
                    var gridPath = Path()
                    let steps: [CGFloat] = [128, 256, 384, 512, 640, 768, 896]
                    for g in steps {
                        gridPath.move(to: pt(g, 0))
                        gridPath.addLine(to: pt(g, 1024))
                        gridPath.move(to: pt(0, g))
                        gridPath.addLine(to: pt(1024, g))
                    }
                    drawCtx.stroke(
                        gridPath,
                        with: .color(Color(red: 26 / 255, green: 34 / 255, blue: 45 / 255)),
                        lineWidth: max(0.5, 2 * u)
                    )

                    var ticks = Path()
                    ticks.move(to: pt(828, 148))
                    ticks.addLine(to: pt(868, 148))
                    ticks.addLine(to: pt(868, 188))
                    ticks.move(to: pt(828, 876))
                    ticks.addLine(to: pt(868, 876))
                    ticks.addLine(to: pt(868, 836))
                    drawCtx.stroke(
                        ticks,
                        with: .color(Color(red: 42 / 255, green: 54 / 255, blue: 70 / 255)),
                        style: StrokeStyle(lineWidth: max(0.75, 6 * u), lineCap: .square)
                    )
                }
            }

            // 1. Left Active Editor Gutter Rail (Terminal Emerald)
            let railWidth: CGFloat = (size < 28 ? 36 : 28) * u
            let railRect = CGRect(x: 176 * u, y: 190 * u, width: railWidth, height: 644 * u)
            let railPath = RoundedRectangle(cornerRadius: railWidth * 0.5, style: .continuous).path(in: railRect)
            drawCtx.fill(railPath, with: .color(primaryColor))

            // 2. Programmer's Slashed Zero Diagonal (drawn beneath the '0' stadium ring)
            var zeroSlash = Path()
            zeroSlash.move(to: pt(618, 418))
            zeroSlash.addLine(to: pt(770, 266))
            drawCtx.stroke(
                zeroSlash,
                with: .color(slashColor),
                style: StrokeStyle(lineWidth: (size < 28 ? 44 : 38) * u, lineCap: .round)
            )

            // 3. Bespoke Monospace Numerals: 3 0 / 1 2
            let inkColor = showTileBackground
                ? Color(red: 241 / 255, green: 245 / 255, blue: 249 / 255)
                : secondaryColor
            let numeralStroke = StrokeStyle(
                lineWidth: (size < 28 ? 60 : 52) * u,
                lineCap: .round,
                lineJoin: .round
            )

            var numerals = Path()
            // Digit '3'
            numerals.move(to: pt(304, 216))
            numerals.addLine(to: pt(484, 216))
            numerals.addLine(to: pt(378, 326))
            numerals.addLine(to: pt(418, 326))
            numerals.addCurve(to: pt(394, 468), control1: pt(498, 326), control2: pt(502, 468))
            numerals.addCurve(to: pt(296, 426), control1: pt(338, 468), control2: pt(308, 450))

            // Digit '0' stadium ring
            let zeroRect = CGRect(x: 602 * u, y: 216 * u, width: 184 * u, height: 252 * u)
            numerals.addPath(RoundedRectangle(cornerRadius: 92 * u, style: .circular).path(in: zeroRect))

            // Digit '1'
            numerals.move(to: pt(326, 612))
            numerals.addLine(to: pt(396, 556))
            numerals.addLine(to: pt(396, 808))
            numerals.move(to: pt(312, 808))
            numerals.addLine(to: pt(480, 808))

            // Digit '2'
            numerals.move(to: pt(604, 620))
            numerals.addCurve(to: pt(696, 556), control1: pt(614, 556), control2: pt(664, 556))
            numerals.addCurve(to: pt(752, 676), control1: pt(772, 556), control2: pt(800, 616))
            numerals.addLine(to: pt(602, 808))
            numerals.addLine(to: pt(790, 808))

            drawCtx.stroke(numerals, with: .color(inkColor), style: numeralStroke)

            // 4. Machined Inner Rim Border
            if showTileBackground {
                let borderInset = max(0.5, 5 * u)
                let borderRect = tileRect.insetBy(dx: borderInset, dy: borderInset)
                let borderPath = RoundedRectangle(cornerRadius: 223 * u, style: .continuous).path(in: borderRect)
                drawCtx.stroke(
                    borderPath,
                    with: .color(Color(red: 48 / 255, green: 62 / 255, blue: 82 / 255)),
                    lineWidth: max(0.8, 10 * u)
                )
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Single-line horizontal `3012_` bespoke developer wordmark (with slashed zero and emerald terminal block cursor).
public struct Brand3012WordmarkView: View {
    public var height: CGFloat = 28
    public var inkColor: Color = .primary
    public var accentColor: Color = Color(red: 16 / 255, green: 185 / 255, blue: 129 / 255)

    public init(
        height: CGFloat = 28,
        inkColor: Color = .primary,
        accentColor: Color = Color(red: 16 / 255, green: 185 / 255, blue: 129 / 255)
    ) {
        self.height = height
        self.inkColor = inkColor
        self.accentColor = accentColor
    }

    public var body: some View {
        let width = height * (476.0 / 104.0)
        Canvas { context, canvasSize in
            let u = canvasSize.height / 104.0
            let pt = { (x: CGFloat, y: CGFloat) in CGPoint(x: x * u, y: y * u) }

            // Emerald Slashed Zero inside '0'
            var slash = Path()
            slash.move(to: pt(126, 78))
            slash.addLine(to: pt(178, 24))
            context.stroke(
                slash,
                with: .color(accentColor),
                style: StrokeStyle(lineWidth: 12 * u, lineCap: .round)
            )

            // Single-line custom vector '3 0 1 2'
            var word = Path()
            // '3'
            word.move(to: pt(10, 10))
            word.addLine(to: pt(66, 10))
            word.addLine(to: pt(32, 46))
            word.addLine(to: pt(46, 46))
            word.addCurve(to: pt(38, 92), control1: pt(72, 46), control2: pt(74, 92))
            word.addCurve(to: pt(7, 78), control1: pt(20, 92), control2: pt(11, 86))

            // '0'
            let zRect = CGRect(x: 120 * u, y: 10 * u, width: 64 * u, height: 82 * u)
            word.addPath(RoundedRectangle(cornerRadius: 32 * u, style: .circular).path(in: zRect))

            // '1'
            word.move(to: pt(242, 28))
            word.addLine(to: pt(266, 10))
            word.addLine(to: pt(266, 92))
            word.move(to: pt(238, 92))
            word.addLine(to: pt(294, 92))

            // '2'
            word.move(to: pt(344, 30))
            word.addCurve(to: pt(375, 10), control1: pt(348, 10), control2: pt(364, 10))
            word.addCurve(to: pt(393, 50), control1: pt(400, 10), control2: pt(410, 30))
            word.addLine(to: pt(342, 92))
            word.addLine(to: pt(408, 92))

            context.stroke(
                word,
                with: .color(inkColor),
                style: StrokeStyle(lineWidth: 16.5 * u, lineCap: .round, lineJoin: .round)
            )

            // Terminal Emerald Underscore Cursor
            let cursorRect = CGRect(x: 430 * u, y: 80 * u, width: 38 * u, height: 14 * u)
            context.fill(
                RoundedRectangle(cornerRadius: 4 * u, style: .continuous).path(in: cursorRect),
                with: .color(accentColor)
            )
        }
        .frame(width: width, height: height)
        .accessibilityLabel("3012")
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
