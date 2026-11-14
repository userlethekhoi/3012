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

/// VS Code Seti-style language & filename icon renderer across all supported languages and special dev files (`.x`, `.xm`, `.h`, `Makefile`, `control`, `.deb`, `.ipa`, etc.).
public struct FileLanguageIconView: View {
    public let language: CodeLanguage
    public let fileName: String?
    public var size: CGFloat = 12

    public init(language: CodeLanguage, fileName: String? = nil, size: CGFloat = 12) {
        self.language = language
        self.fileName = fileName
        self.size = size
    }

    private enum IconGlyph {
        case monogram(String, Color)
        case symbol(String, Color)
    }

    public var body: some View {
        let frameSide = size + 5
        Group {
            switch resolvedGlyph() {
            case .monogram(let text, let color):
                Text(text)
                    .font(.system(size: max(8, size * (text.count >= 3 ? 0.68 : (text.count == 2 ? 0.78 : 0.94))), weight: .heavy, design: .rounded))
                    .foregroundColor(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
            case .symbol(let symbolName, let color):
                Image(systemName: symbolName)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: size, weight: .semibold))
                    .foregroundColor(color)
            }
        }
        .frame(width: frameSide, height: frameSide, alignment: .center)
    }

    private func resolvedGlyph() -> IconGlyph {
        if let rawName = fileName?.trimmingCharacters(in: .whitespacesAndNewlines), !rawName.isEmpty {
            let lowerName = (rawName as NSString).lastPathComponent.lowercased()
            let ext = (lowerName as NSString).pathExtension

            // Special exact filenames (VS Code Seti style)
            if lowerName == "makefile" || lowerName == "gnumakefile" {
                return .symbol("hammer.fill", Color(red: 0.89, green: 0.48, blue: 0.22))
            }
            if lowerName == "control" {
                return .symbol("shippingbox.fill", Color(red: 0.92, green: 0.54, blue: 0.22))
            }
            if lowerName == "dockerfile" || lowerName.hasPrefix("dockerfile.") {
                return .symbol("shippingbox.circle.fill", Color(red: 0.22, green: 0.72, blue: 0.95))
            }
            if lowerName == "package.swift" {
                return .symbol("swift", Color(red: 0.97, green: 0.45, blue: 0.15))
            }
            if lowerName == "package.json" || lowerName == "package-lock.json" || lowerName == "tsconfig.json" {
                return .monogram("{}", Color(red: 0.94, green: 0.76, blue: 0.24))
            }
            if lowerName == "cmakelists.txt" {
                return .monogram("CM", Color(red: 0.22, green: 0.82, blue: 0.62))
            }
            if lowerName == ".gitignore" || lowerName == ".gitattributes" || lowerName == ".gitmodules" {
                return .symbol("arrow.triangle.branch", Color(red: 0.95, green: 0.34, blue: 0.22))
            }
            if lowerName == ".env" || lowerName.hasPrefix(".env.") {
                return .symbol("key.fill", Color(red: 0.96, green: 0.74, blue: 0.20))
            }
            if lowerName == "xtool.yml" || lowerName == "project.yml" {
                return .symbol("wrench.and.screwdriver.fill", Color(red: 0.76, green: 0.48, blue: 0.98))
            }

            // Extension-specific VS Code overrides (especially Tweaks, Headers, Archives & Binaries)
            switch ext {
            case "x", "xi":
                return .monogram(".x", Color(red: 0.76, green: 0.42, blue: 0.98))
            case "xm", "xmi":
                return .monogram("xm", Color(red: 0.88, green: 0.40, blue: 0.96))
            case "h":
                return .monogram("H", Color(red: 0.64, green: 0.46, blue: 0.88))
            case "hpp", "hh", "hxx":
                return .monogram("H+", Color(red: 0.64, green: 0.46, blue: 0.88))
            case "m":
                return .monogram("M", Color(red: 0.34, green: 0.66, blue: 0.98))
            case "mm":
                return .monogram("M+", Color(red: 0.46, green: 0.56, blue: 0.98))
            case "c":
                return .monogram("C", Color(red: 0.32, green: 0.64, blue: 0.96))
            case "cpp", "cc", "cxx":
                return .monogram("C++", Color(red: 0.32, green: 0.64, blue: 0.96))
            case "jsx":
                return .symbol("atom", Color(red: 0.96, green: 0.78, blue: 0.22))
            case "tsx":
                return .symbol("atom", Color(red: 0.24, green: 0.72, blue: 0.98))
            case "plist", "entitlements":
                return .symbol("checklist", Color(red: 0.95, green: 0.55, blue: 0.24))
            case "svg":
                return .symbol("circle.square.fill", Color(red: 0.98, green: 0.72, blue: 0.20))
            case "deb", "ipa", "apk":
                return .symbol("shippingbox.fill", Color(red: 0.26, green: 0.82, blue: 0.52))
            case "dylib", "so", "a", "framework":
                return .symbol("cpu.fill", Color(red: 0.56, green: 0.64, blue: 0.98))
            case "zip", "tar", "gz", "7z", "rar":
                return .symbol("doc.zipper", Color(red: 0.82, green: 0.62, blue: 0.36))
            case "png", "jpg", "jpeg", "gif", "webp", "ico":
                return .symbol("photo.fill", Color(red: 0.64, green: 0.48, blue: 0.94))
            case "log":
                return .symbol("doc.text.magnifyingglass", Color(red: 0.58, green: 0.64, blue: 0.72))
            default:
                break
            }
        }

        // Language-level VS Code Seti icons
        switch language {
        case .html:
            return .monogram("<>", Color(red: 0.94, green: 0.40, blue: 0.18))
        case .css:
            return .monogram("#", Color(red: 0.26, green: 0.66, blue: 0.96))
        case .scss:
            return .monogram("S", Color(red: 0.92, green: 0.35, blue: 0.62))
        case .javascript:
            return .monogram("JS", Color(red: 0.96, green: 0.80, blue: 0.20))
        case .typescript:
            return .monogram("TS", Color(red: 0.24, green: 0.56, blue: 0.96))
        case .tsx:
            return .symbol("atom", Color(red: 0.24, green: 0.74, blue: 0.98))
        case .vue:
            return .monogram("V", Color(red: 0.26, green: 0.74, blue: 0.52))
        case .svelte:
            return .monogram("S", Color(red: 0.98, green: 0.34, blue: 0.14))
        case .astro:
            return .symbol("sparkles", Color(red: 0.98, green: 0.42, blue: 0.24))
        case .graphql:
            return .monogram("GQ", Color(red: 0.90, green: 0.30, blue: 0.64))
        case .c:
            return .monogram("C", Color(red: 0.32, green: 0.64, blue: 0.96))
        case .cpp:
            return .monogram("C++", Color(red: 0.32, green: 0.64, blue: 0.96))
        case .objectiveC:
            return .monogram("M", Color(red: 0.34, green: 0.66, blue: 0.98))
        case .rust:
            return .symbol("gearshape.2.fill", Color(red: 0.90, green: 0.48, blue: 0.28))
        case .go:
            return .monogram("Go", Color(red: 0.00, green: 0.74, blue: 0.88))
        case .zig:
            return .monogram("Z", Color(red: 0.96, green: 0.68, blue: 0.16))
        case .dlang:
            return .monogram("D", Color(red: 0.84, green: 0.32, blue: 0.30))
        case .nim:
            return .monogram("Nm", Color(red: 0.96, green: 0.76, blue: 0.22))
        case .crystal:
            return .symbol("diamond", Color(red: 0.74, green: 0.82, blue: 0.94))
        case .assembly:
            return .symbol("cpu", Color(red: 0.52, green: 0.58, blue: 0.96))
        case .swift:
            return .symbol("swift", Color(red: 0.97, green: 0.45, blue: 0.15))
        case .dart:
            return .monogram("D", Color(red: 0.08, green: 0.74, blue: 0.82))
        case .java:
            return .symbol("cup.and.saucer.fill", Color(red: 0.92, green: 0.34, blue: 0.28))
        case .kotlin:
            return .monogram("K", Color(red: 0.64, green: 0.38, blue: 0.98))
        case .scala:
            return .monogram("Sc", Color(red: 0.90, green: 0.30, blue: 0.28))
        case .groovy:
            return .monogram("Gv", Color(red: 0.38, green: 0.64, blue: 0.86))
        case .csharp:
            return .monogram("C#", Color(red: 0.48, green: 0.76, blue: 0.38))
        case .python:
            return .monogram("PY", Color(red: 0.32, green: 0.66, blue: 0.96))
        case .php:
            return .monogram("php", Color(red: 0.56, green: 0.48, blue: 0.94))
        case .ruby:
            return .symbol("diamond.fill", Color(red: 0.88, green: 0.25, blue: 0.33))
        case .perl:
            return .monogram("Pl", Color(red: 0.34, green: 0.62, blue: 0.86))
        case .lua:
            return .symbol("moon.circle.fill", Color(red: 0.30, green: 0.54, blue: 0.96))
        case .r:
            return .monogram("R", Color(red: 0.26, green: 0.56, blue: 0.92))
        case .julia:
            return .symbol("circle.grid.2x2.fill", Color(red: 0.62, green: 0.42, blue: 0.92))
        case .elixir:
            return .symbol("drop.fill", Color(red: 0.64, green: 0.40, blue: 0.92))
        case .erlang:
            return .monogram("e", Color(red: 0.84, green: 0.24, blue: 0.36))
        case .haskell:
            return .monogram("λ", Color(red: 0.62, green: 0.44, blue: 0.92))
        case .ocaml:
            return .monogram("Ml", Color(red: 0.94, green: 0.56, blue: 0.20))
        case .elm:
            return .monogram("El", Color(red: 0.36, green: 0.72, blue: 0.88))
        case .lisp:
            return .monogram("()", Color(red: 0.78, green: 0.54, blue: 0.92))
        case .pascal:
            return .monogram("Ps", Color(red: 0.34, green: 0.64, blue: 0.92))
        case .solidity:
            return .symbol("hexagon.fill", Color(red: 0.56, green: 0.64, blue: 0.82))
        case .sql:
            return .symbol("cylinder.split.1x2.fill", Color(red: 0.26, green: 0.72, blue: 0.92))
        case .json, .json5:
            return .monogram("{}", Color(red: 0.95, green: 0.76, blue: 0.20))
        case .yaml:
            return .monogram("Y!", Color(red: 0.92, green: 0.34, blue: 0.58))
        case .toml:
            return .monogram("T", Color(red: 0.86, green: 0.48, blue: 0.26))
        case .xml:
            return .monogram("</>", Color(red: 0.94, green: 0.52, blue: 0.20))
        case .protobuf:
            return .monogram("Pb", Color(red: 0.44, green: 0.72, blue: 0.94))
        case .ini:
            return .symbol("slider.horizontal.3", Color(red: 0.64, green: 0.70, blue: 0.78))
        case .shell, .fish:
            return .monogram("$_", Color(red: 0.30, green: 0.84, blue: 0.52))
        case .powershell:
            return .monogram(">_", Color(red: 0.32, green: 0.66, blue: 0.96))
        case .dockerfile:
            return .symbol("shippingbox.circle.fill", Color(red: 0.22, green: 0.72, blue: 0.95))
        case .makefile:
            return .symbol("hammer.fill", Color(red: 0.89, green: 0.48, blue: 0.22))
        case .cmake:
            return .monogram("CM", Color(red: 0.22, green: 0.82, blue: 0.62))
        case .hcl, .bicep:
            return .monogram("TF", Color(red: 0.64, green: 0.42, blue: 0.96))
        case .nix:
            return .symbol("snowflake", Color(red: 0.42, green: 0.70, blue: 0.98))
        case .markdown:
            return .monogram("M↓", Color(red: 0.32, green: 0.68, blue: 0.96))
        case .latex:
            return .monogram("Te", Color(red: 0.22, green: 0.76, blue: 0.64))
        case .regex:
            return .monogram(".*", Color(red: 0.88, green: 0.54, blue: 0.28))
        case .diff:
            return .symbol("plus.forwardslash.minus", Color(red: 0.48, green: 0.82, blue: 0.56))
        case .plainText:
            return .symbol("doc.text", Color(red: 0.60, green: 0.66, blue: 0.74))
        }
    }
}
