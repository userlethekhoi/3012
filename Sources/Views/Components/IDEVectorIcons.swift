import Foundation
import SwiftUI

// MARK: - Aligned Form / List Action Buttons (prevents SwiftUI .bordered shifting & truncation)

public enum IDEButtonProminence {
    case prominent
    case secondary
    case destructive
}

public struct IDEActionButton<LabelContent: View>: View {
    private let prominence: IDEButtonProminence
    private let tint: Color
    private let fullWidth: Bool
    private let compact: Bool
    private let action: () -> Void
    private let label: () -> LabelContent

    @Environment(\.isEnabled) private var isEnabled

    public init(
        prominence: IDEButtonProminence = .prominent,
        tint: Color = .accentColor,
        fullWidth: Bool = true,
        compact: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> LabelContent
    ) {
        self.prominence = prominence
        self.tint = tint
        self.fullWidth = fullWidth
        self.compact = compact
        self.action = action
        self.label = label
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                label()
            }
            .font(.system(size: compact ? 12.5 : 13.5, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.84)
            .foregroundColor(foreground)
            .frame(maxWidth: fullWidth ? .infinity : nil, alignment: .center)
            .padding(.horizontal, compact ? 12 : 14)
            .padding(.vertical, compact ? 8 : 10)
            .background(
                RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous)
                    .fill(backgroundFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous)
                    .stroke(borderStroke, lineWidth: 0.75)
            )
            .contentShape(RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous))
            .opacity(isEnabled ? 1.0 : 0.45)
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        switch prominence {
        case .prominent: return .white
        case .secondary: return tint
        case .destructive: return .red
        }
    }

    private var backgroundFill: Color {
        switch prominence {
        case .prominent: return tint
        case .secondary: return tint.opacity(0.13)
        case .destructive: return Color.red.opacity(0.13)
        }
    }

    private var borderStroke: Color {
        switch prominence {
        case .prominent: return tint.opacity(0.2)
        case .secondary: return tint.opacity(0.24)
        case .destructive: return Color.red.opacity(0.28)
        }
    }
}

public struct IDEPillButton<LabelContent: View>: View {
    private let prominence: IDEButtonProminence
    private let tint: Color
    private let action: () -> Void
    private let label: () -> LabelContent

    @Environment(\.isEnabled) private var isEnabled

    public init(
        prominence: IDEButtonProminence = .prominent,
        tint: Color = .accentColor,
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> LabelContent
    ) {
        self.prominence = prominence
        self.tint = tint
        self.action = action
        self.label = label
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                label()
            }
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundColor(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 6.5)
            .background(Capsule(style: .continuous).fill(backgroundFill))
            .overlay(Capsule(style: .continuous).stroke(borderStroke, lineWidth: 0.75))
            .contentShape(Capsule(style: .continuous))
            .opacity(isEnabled ? 1.0 : 0.45)
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        switch prominence {
        case .prominent: return .white
        case .secondary: return tint
        case .destructive: return .red
        }
    }

    private var backgroundFill: Color {
        switch prominence {
        case .prominent: return tint
        case .secondary: return tint.opacity(0.13)
        case .destructive: return Color.red.opacity(0.13)
        }
    }

    private var borderStroke: Color {
        switch prominence {
        case .prominent: return Color.clear
        case .secondary: return tint.opacity(0.24)
        case .destructive: return Color.red.opacity(0.28)
        }
    }
}

// MARK: - Precision Geometric 3012 Emblem (`</>` Dark-Glass + Luminous Emerald/Cyan)

/// Bespoke crisp 120Hz vector brand emblem matching the iOS Home Screen AppIcon
/// on an exact 1024-unit geometric grid.
public struct IDECodeMarkVector: View {
    public var size: CGFloat = 22
    public var primaryColor: Color = Color(red: 16 / 255, green: 185 / 255, blue: 129 / 255) // #10B981 Terminal Emerald
    public var slashColor: Color = Color(red: 56 / 255, green: 189 / 255, blue: 248 / 255)   // #38BDF8 Cyber Sky
    public var secondaryColor: Color = Color(red: 241 / 255, green: 245 / 255, blue: 249 / 255) // #F1F5F9 Titanium Chalk
    public var showTileBackground: Bool = true

    public init(
        size: CGFloat = 22,
        primaryColor: Color = Color(red: 16 / 255, green: 185 / 255, blue: 129 / 255),
        slashColor: Color = Color(red: 56 / 255, green: 189 / 255, blue: 248 / 255),
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
                let squircle = RoundedRectangle(cornerRadius: 230 * u, style: .continuous).path(in: tileRect)
                drawCtx.clip(to: squircle)

                let bgTop = Color(red: 15 / 255, green: 23 / 255, blue: 42 / 255)   // #0F172A Deep Slate
                let bgBot = Color(red: 8 / 255, green: 12 / 255, blue: 22 / 255)    // #080C16 Obsidian Night
                drawCtx.fill(
                    squircle,
                    with: .linearGradient(
                        Gradient(colors: [bgTop, bgBot]),
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: side, y: side)
                    )
                )

                // Ambient emerald/cyan core glow behind the `</>` mark
                let glowRect = CGRect(x: 160 * u, y: 140 * u, width: 704 * u, height: 704 * u)
                drawCtx.fill(
                    Path(ellipseIn: glowRect),
                    with: .radialGradient(
                        Gradient(colors: [
                            primaryColor.opacity(0.24),
                            slashColor.opacity(0.10),
                            Color.clear
                        ]),
                        center: pt(512, 490),
                        startRadius: 20 * u,
                        endRadius: 380 * u
                    )
                )

                // Top-left dark-glass specular sheen
                if size >= 28 {
                    var sheen = Path()
                    sheen.move(to: pt(0, 0))
                    sheen.addLine(to: pt(760, 0))
                    sheen.addLine(to: pt(0, 560))
                    sheen.closeSubpath()
                    drawCtx.fill(
                        sheen,
                        with: .linearGradient(
                            Gradient(colors: [Color.white.opacity(0.08), Color.clear]),
                            startPoint: pt(0, 0),
                            endPoint: pt(380, 380)
                        )
                    )
                }
            }

            let inkColor = showTileBackground
                ? Color(red: 241 / 255, green: 245 / 255, blue: 249 / 255)
                : secondaryColor
            let strokeW: CGFloat = (size < 28 ? 82 : 68) * u
            let chevronStyle = StrokeStyle(lineWidth: strokeW, lineCap: .round, lineJoin: .round)

            // Left `<` bracket
            var leftBracket = Path()
            leftBracket.move(to: pt(360, 326))
            leftBracket.addLine(to: pt(192, 488))
            leftBracket.addLine(to: pt(360, 650))
            drawCtx.stroke(leftBracket, with: .color(inkColor), style: chevronStyle)

            // Right `>` bracket
            var rightBracket = Path()
            rightBracket.move(to: pt(664, 326))
            rightBracket.addLine(to: pt(832, 488))
            rightBracket.addLine(to: pt(664, 650))
            drawCtx.stroke(rightBracket, with: .color(inkColor), style: chevronStyle)

            // Center diagonal `/` slash in luminous Emerald -> Cyan gradient
            var slash = Path()
            slash.move(to: pt(438, 704))
            slash.addLine(to: pt(586, 272))
            drawCtx.stroke(
                slash,
                with: .linearGradient(
                    Gradient(colors: [primaryColor, slashColor]),
                    startPoint: pt(438, 704),
                    endPoint: pt(586, 272)
                ),
                style: StrokeStyle(lineWidth: strokeW * 1.06, lineCap: .round)
            )

            // Signature active prompt bar `_` at base
            let barW: CGFloat = (size < 28 ? 260 : 228) * u
            let barH: CGFloat = (size < 28 ? 52 : 42) * u
            let barRect = CGRect(x: (1024 * u - barW) * 0.5, y: 786 * u, width: barW, height: barH)
            drawCtx.fill(
                RoundedRectangle(cornerRadius: barH * 0.5, style: .continuous).path(in: barRect),
                with: .color(primaryColor)
            )

            if showTileBackground {
                let borderInset = max(0.5, 6 * u)
                let borderRect = tileRect.insetBy(dx: borderInset, dy: borderInset)
                let borderPath = RoundedRectangle(cornerRadius: 224 * u, style: .continuous).path(in: borderRect)
                drawCtx.stroke(
                    borderPath,
                    with: .linearGradient(
                        Gradient(colors: [
                            Color.white.opacity(0.24),
                            Color(red: 56 / 255, green: 189 / 255, blue: 248 / 255).opacity(0.18),
                            Color.white.opacity(0.06)
                        ]),
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: side, y: side)
                    ),
                    lineWidth: max(0.75, 12 * u)
                )
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Crisp vector `3012` developer wordmark paired with terminal status cursor.
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
        HStack(spacing: max(3, height * 0.16)) {
            Text("3012")
                .font(.system(size: max(12, height * 0.92), weight: .heavy, design: .monospaced))
                .foregroundColor(inkColor)
                .lineLimit(1)
            RoundedRectangle(cornerRadius: max(1.5, height * 0.1), style: .continuous)
                .fill(accentColor)
                .frame(width: max(6, height * 0.48), height: max(2.5, height * 0.16))
                .offset(y: height * 0.24)
        }
        .frame(height: height)
        .accessibilityLabel("3012")
    }
}

// MARK: - VS Code Seti-Style File Language Tile Icons (100% iOS 15.0+ SF Symbols & Monograms)

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

        var tint: Color {
            switch self {
            case .monogram(_, let c), .symbol(_, let c): return c
            }
        }
    }

    public var body: some View {
        let glyph = resolvedGlyph()
        let tint = glyph.tint
        let frameSide = max(15, size + 6.5)
        let corner = max(3.5, frameSide * 0.25)

        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(tint.opacity(0.14))
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .stroke(tint.opacity(0.28), lineWidth: 0.6)

            switch glyph {
            case .monogram(let text, let color):
                Text(text)
                    .font(.system(
                        size: max(7, size * (text.count >= 3 ? 0.56 : (text.count == 2 ? 0.68 : 0.82))),
                        weight: .heavy,
                        design: .monospaced
                    ))
                    .foregroundColor(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
            case .symbol(let symbolName, let color):
                Image(systemName: symbolName)
                    .font(.system(size: max(8.5, size * 0.82), weight: .semibold))
                    .foregroundColor(color)
            }
        }
        .frame(width: frameSide, height: frameSide, alignment: .center)
    }

    private func resolvedGlyph() -> IconGlyph {
        if let rawName = fileName?.trimmingCharacters(in: .whitespacesAndNewlines), !rawName.isEmpty {
            let lowerName = (rawName as NSString).lastPathComponent.lowercased()
            let ext = (lowerName as NSString).pathExtension

            if lowerName == "makefile" || lowerName == "gnumakefile" {
                return .symbol("hammer.fill", Color(red: 0.92, green: 0.50, blue: 0.24))
            }
            if lowerName == "control" {
                return .symbol("shippingbox.fill", Color(red: 0.94, green: 0.56, blue: 0.24))
            }
            if lowerName == "dockerfile" || lowerName.hasPrefix("dockerfile.") {
                return .symbol("shippingbox.fill", Color(red: 0.22, green: 0.72, blue: 0.95))
            }
            if lowerName == "package.swift" {
                return .symbol("swift", Color(red: 0.98, green: 0.45, blue: 0.16))
            }
            if lowerName == "package.json" || lowerName == "package-lock.json" || lowerName == "tsconfig.json" {
                return .monogram("{}", Color(red: 0.95, green: 0.76, blue: 0.24))
            }
            if lowerName == "cmakelists.txt" {
                return .monogram("CM", Color(red: 0.20, green: 0.82, blue: 0.62))
            }
            if lowerName == ".gitignore" || lowerName == ".gitattributes" || lowerName == ".gitmodules" {
                return .symbol("arrow.triangle.branch", Color(red: 0.95, green: 0.36, blue: 0.24))
            }
            if lowerName == ".env" || lowerName.hasPrefix(".env.") {
                return .symbol("key.fill", Color(red: 0.96, green: 0.74, blue: 0.20))
            }
            if lowerName == "xtool.yml" || lowerName == "project.yml" {
                return .symbol("wrench.and.screwdriver.fill", Color(red: 0.76, green: 0.48, blue: 0.98))
            }

            switch ext {
            case "x", "xi":
                return .monogram(".x", Color(red: 0.76, green: 0.44, blue: 0.98))
            case "xm", "xmi":
                return .monogram("xm", Color(red: 0.88, green: 0.42, blue: 0.96))
            case "h":
                return .monogram("H", Color(red: 0.66, green: 0.48, blue: 0.92))
            case "hpp", "hh", "hxx":
                return .monogram("H+", Color(red: 0.66, green: 0.48, blue: 0.92))
            case "m":
                return .monogram("M", Color(red: 0.34, green: 0.68, blue: 0.98))
            case "mm":
                return .monogram("M+", Color(red: 0.48, green: 0.58, blue: 0.98))
            case "c":
                return .monogram("C", Color(red: 0.32, green: 0.66, blue: 0.98))
            case "cpp", "cc", "cxx":
                return .monogram("C++", Color(red: 0.32, green: 0.66, blue: 0.98))
            case "jsx":
                return .symbol("atom", Color(red: 0.96, green: 0.78, blue: 0.22))
            case "tsx":
                return .symbol("atom", Color(red: 0.24, green: 0.74, blue: 0.98))
            case "plist", "entitlements":
                return .symbol("checklist", Color(red: 0.95, green: 0.56, blue: 0.24))
            case "svg":
                return .symbol("circle.square.fill", Color(red: 0.98, green: 0.72, blue: 0.20))
            case "deb", "ipa", "apk":
                return .symbol("shippingbox.fill", Color(red: 0.24, green: 0.82, blue: 0.54))
            case "dylib", "so", "a", "framework":
                return .symbol("cpu.fill", Color(red: 0.56, green: 0.66, blue: 0.98))
            case "zip", "tar", "gz", "7z", "rar":
                return .symbol("doc.zipper", Color(red: 0.84, green: 0.62, blue: 0.36))
            case "png", "jpg", "jpeg", "gif", "webp", "ico":
                return .symbol("photo.fill", Color(red: 0.64, green: 0.50, blue: 0.96))
            case "log":
                return .symbol("doc.text.magnifyingglass", Color(red: 0.58, green: 0.66, blue: 0.74))
            default:
                break
            }
        }

        switch language {
        case .html:
            return .monogram("<>", Color(red: 0.94, green: 0.42, blue: 0.20))
        case .css:
            return .monogram("#", Color(red: 0.26, green: 0.68, blue: 0.98))
        case .scss:
            return .monogram("S", Color(red: 0.92, green: 0.36, blue: 0.64))
        case .javascript:
            return .monogram("JS", Color(red: 0.96, green: 0.80, blue: 0.20))
        case .typescript:
            return .monogram("TS", Color(red: 0.24, green: 0.58, blue: 0.98))
        case .tsx:
            return .symbol("atom", Color(red: 0.24, green: 0.74, blue: 0.98))
        case .vue:
            return .monogram("V", Color(red: 0.24, green: 0.78, blue: 0.54))
        case .svelte:
            return .monogram("S", Color(red: 0.98, green: 0.36, blue: 0.16))
        case .astro:
            return .monogram("As", Color(red: 0.98, green: 0.44, blue: 0.24))
        case .graphql:
            return .monogram("GQ", Color(red: 0.90, green: 0.32, blue: 0.66))
        case .c:
            return .monogram("C", Color(red: 0.32, green: 0.66, blue: 0.98))
        case .cpp:
            return .monogram("C++", Color(red: 0.32, green: 0.66, blue: 0.98))
        case .objectiveC:
            return .monogram("M", Color(red: 0.34, green: 0.68, blue: 0.98))
        case .rust:
            return .symbol("gearshape.2.fill", Color(red: 0.90, green: 0.48, blue: 0.28))
        case .go:
            return .monogram("Go", Color(red: 0.00, green: 0.76, blue: 0.90))
        case .zig:
            return .monogram("Z", Color(red: 0.96, green: 0.68, blue: 0.18))
        case .dlang:
            return .monogram("D", Color(red: 0.86, green: 0.34, blue: 0.32))
        case .nim:
            return .monogram("Nm", Color(red: 0.96, green: 0.76, blue: 0.22))
        case .crystal:
            return .symbol("diamond", Color(red: 0.74, green: 0.82, blue: 0.94))
        case .assembly:
            return .symbol("cpu", Color(red: 0.52, green: 0.60, blue: 0.96))
        case .swift:
            return .symbol("swift", Color(red: 0.98, green: 0.45, blue: 0.16))
        case .dart:
            return .monogram("D", Color(red: 0.08, green: 0.76, blue: 0.84))
        case .java:
            return .symbol("cup.and.saucer.fill", Color(red: 0.92, green: 0.36, blue: 0.28))
        case .kotlin:
            return .monogram("K", Color(red: 0.66, green: 0.40, blue: 0.98))
        case .scala:
            return .monogram("Sc", Color(red: 0.90, green: 0.32, blue: 0.28))
        case .groovy:
            return .monogram("Gv", Color(red: 0.38, green: 0.66, blue: 0.88))
        case .csharp:
            return .monogram("C#", Color(red: 0.48, green: 0.78, blue: 0.38))
        case .python:
            return .monogram("PY", Color(red: 0.32, green: 0.68, blue: 0.98))
        case .php:
            return .monogram("php", Color(red: 0.58, green: 0.50, blue: 0.96))
        case .ruby:
            return .symbol("diamond.fill", Color(red: 0.90, green: 0.26, blue: 0.34))
        case .perl:
            return .monogram("Pl", Color(red: 0.34, green: 0.64, blue: 0.88))
        case .lua:
            return .symbol("moon.circle.fill", Color(red: 0.30, green: 0.56, blue: 0.98))
        case .r:
            return .monogram("R", Color(red: 0.26, green: 0.58, blue: 0.94))
        case .julia:
            return .symbol("circle.grid.2x2.fill", Color(red: 0.64, green: 0.44, blue: 0.94))
        case .elixir:
            return .symbol("drop.fill", Color(red: 0.66, green: 0.42, blue: 0.94))
        case .erlang:
            return .monogram("e", Color(red: 0.86, green: 0.26, blue: 0.38))
        case .haskell:
            return .monogram("λ", Color(red: 0.64, green: 0.46, blue: 0.94))
        case .ocaml:
            return .monogram("Ml", Color(red: 0.94, green: 0.58, blue: 0.20))
        case .elm:
            return .monogram("El", Color(red: 0.36, green: 0.74, blue: 0.90))
        case .lisp:
            return .monogram("()", Color(red: 0.78, green: 0.56, blue: 0.94))
        case .pascal:
            return .monogram("Ps", Color(red: 0.34, green: 0.66, blue: 0.94))
        case .solidity:
            return .symbol("hexagon.fill", Color(red: 0.58, green: 0.66, blue: 0.86))
        case .sql:
            return .symbol("cylinder.split.1x2.fill", Color(red: 0.26, green: 0.74, blue: 0.94))
        case .json, .json5:
            return .monogram("{}", Color(red: 0.95, green: 0.76, blue: 0.20))
        case .yaml:
            return .monogram("Y!", Color(red: 0.92, green: 0.36, blue: 0.60))
        case .toml:
            return .monogram("T", Color(red: 0.88, green: 0.50, blue: 0.26))
        case .xml:
            return .monogram("</>", Color(red: 0.94, green: 0.54, blue: 0.20))
        case .protobuf:
            return .monogram("Pb", Color(red: 0.44, green: 0.74, blue: 0.96))
        case .ini:
            return .symbol("slider.horizontal.3", Color(red: 0.64, green: 0.72, blue: 0.80))
        case .shell, .fish:
            return .monogram("$_", Color(red: 0.28, green: 0.86, blue: 0.54))
        case .powershell:
            return .monogram(">_", Color(red: 0.32, green: 0.68, blue: 0.98))
        case .dockerfile:
            return .symbol("shippingbox.fill", Color(red: 0.22, green: 0.72, blue: 0.95))
        case .makefile:
            return .symbol("hammer.fill", Color(red: 0.92, green: 0.50, blue: 0.24))
        case .cmake:
            return .monogram("CM", Color(red: 0.20, green: 0.82, blue: 0.62))
        case .hcl, .bicep:
            return .monogram("TF", Color(red: 0.64, green: 0.44, blue: 0.96))
        case .nix:
            return .symbol("snowflake", Color(red: 0.42, green: 0.72, blue: 0.98))
        case .markdown:
            return .monogram("M↓", Color(red: 0.32, green: 0.68, blue: 0.98))
        case .latex:
            return .monogram("Te", Color(red: 0.22, green: 0.78, blue: 0.66))
        case .regex:
            return .monogram(".*", Color(red: 0.90, green: 0.56, blue: 0.28))
        case .diff:
            return .symbol("slash.circle", Color(red: 0.48, green: 0.84, blue: 0.56))
        case .plainText:
            return .symbol("doc.text", Color(red: 0.60, green: 0.68, blue: 0.76))
        }
    }
}
