import SwiftUI
import WebKit

public struct MarkdownMermaidPreviewView: UIViewRepresentable {
    public let markdown: String
    public let palette: IDEColorPalette

    public init(markdown: String, palette: IDEColorPalette) {
        self.markdown = markdown
        self.palette = palette
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = UIColor(hexString: palette.editorBackground)
        webView.scrollView.backgroundColor = UIColor(hexString: palette.editorBackground)
        let html = Self.buildHTML(markdown: markdown, palette: palette)
        context.coordinator.lastHTML = html
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    public func updateUIView(_ webView: WKWebView, context: Context) {
        webView.backgroundColor = UIColor(hexString: palette.editorBackground)
        webView.scrollView.backgroundColor = UIColor(hexString: palette.editorBackground)
        let html = Self.buildHTML(markdown: markdown, palette: palette)
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    public final class Coordinator {
        var lastHTML: String = ""
    }

    // MARK: - Lightweight Native Markdown + Mermaid HTML Compiler
    private static func buildHTML(markdown: String, palette: IDEColorPalette) -> String {
        let bodyHTML = convertMarkdownToHTML(markdown)
        let mermaidTheme = palette.isDark ? "dark" : "default"

        return """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="UTF-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1.0" />
          <style>
            :root {
              color-scheme: \(palette.isDark ? "dark" : "light");
            }
            * { box-sizing: border-box; }
            body {
              margin: 0;
              padding: 18px 20px 40px 20px;
              font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
              font-size: 14.5px;
              line-height: 1.62;
              background: \(palette.editorBackground);
              color: \(palette.foreground);
              word-wrap: break-word;
            }
            h1, h2, h3, h4 {
              margin-top: 1.2em;
              margin-bottom: 0.45em;
              line-height: 1.3;
              color: \(palette.foreground);
            }
            h1 {
              font-size: 1.55em;
              padding-bottom: 0.25em;
              border-bottom: 1px solid \(palette.currentLineBackground);
            }
            h2 {
              font-size: 1.3em;
              padding-bottom: 0.2em;
              border-bottom: 1px solid \(palette.currentLineBackground);
            }
            h3 { font-size: 1.12em; }
            p { margin: 0.65em 0; }
            a { color: \(palette.accent); text-decoration: none; }
            code {
              font-family: Menlo, ui-monospace, SFMono-Regular, monospace;
              font-size: 0.88em;
              background: \(palette.currentLineBackground);
              color: \(palette.function);
              padding: 2px 6px;
              border-radius: 5px;
            }
            pre {
              background: \(palette.sidebarBackground);
              border: 1px solid \(palette.currentLineBackground);
              border-radius: 9px;
              padding: 12px 14px;
              overflow-x: auto;
              margin: 0.85em 0;
            }
            pre code {
              background: transparent;
              color: \(palette.foreground);
              padding: 0;
              font-size: 12.5px;
            }
            blockquote {
              margin: 0.8em 0;
              padding: 6px 14px;
              border-left: 3px solid \(palette.accent);
              background: \(palette.sidebarBackground);
              border-radius: 0 6px 6px 0;
              color: \(palette.gutterForeground);
            }
            ul, ol { padding-left: 22px; margin: 0.6em 0; }
            li { margin: 0.25em 0; }
            hr {
              border: none;
              border-top: 1px solid \(palette.currentLineBackground);
              margin: 1.2em 0;
            }
            table {
              width: 100%;
              border-collapse: collapse;
              margin: 0.9em 0;
              font-size: 13px;
            }
            th, td {
              border: 1px solid \(palette.currentLineBackground);
              padding: 7px 10px;
              text-align: left;
            }
            th {
              background: \(palette.sidebarBackground);
              font-weight: 600;
            }
            .mermaid {
              background: \(palette.sidebarBackground);
              border: 1px solid \(palette.currentLineBackground);
              border-radius: 10px;
              padding: 12px;
              margin: 0.9em 0;
              overflow-x: auto;
              text-align: center;
            }
          </style>
        </head>
        <body>
          \(bodyHTML)
          <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
          <script>
            if (window.mermaid) {
              mermaid.initialize({ startOnLoad: true, theme: "\(mermaidTheme)", securityLevel: "loose" });
            }
          </script>
        </body>
        </html>
        """
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func formatInline(_ raw: String) -> String {
        var out = escapeHTML(raw)
        // Inline code `...`
        if let codeRx = try? NSRegularExpression(pattern: #"`([^`]+)`"#) {
            out = codeRx.stringByReplacingMatches(in: out, range: NSRange(location: 0, length: (out as NSString).length), withTemplate: "<code>$1</code>")
        }
        // Bold **...**
        if let boldRx = try? NSRegularExpression(pattern: #"\*\*([^*]+)\*\*"#) {
            out = boldRx.stringByReplacingMatches(in: out, range: NSRange(location: 0, length: (out as NSString).length), withTemplate: "<strong>$1</strong>")
        }
        // Italic *...*
        if let italicRx = try? NSRegularExpression(pattern: #"(?<!\*)\*([^*]+)\*(?!\*)"#) {
            out = italicRx.stringByReplacingMatches(in: out, range: NSRange(location: 0, length: (out as NSString).length), withTemplate: "<em>$1</em>")
        }
        // Links [label](url)
        if let linkRx = try? NSRegularExpression(pattern: #"\[([^\]]+)\]\(([^)]+)\)"#) {
            out = linkRx.stringByReplacingMatches(in: out, range: NSRange(location: 0, length: (out as NSString).length), withTemplate: "<a href=\"$2\">$1</a>")
        }
        return out
    }

    private static func convertMarkdownToHTML(_ md: String) -> String {
        let lines = md.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var html: [String] = []
        var inCodeFence = false
        var fenceLang = ""
        var fenceLines: [String] = []
        var inList = false
        var inTable = false

        func closeOpenContainers() {
            if inList {
                html.append("</ul>")
                inList = false
            }
            if inTable {
                html.append("</tbody></table>")
                inTable = false
            }
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                closeOpenContainers()
                if !inCodeFence {
                    inCodeFence = true
                    fenceLang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces).lowercased()
                    fenceLines = []
                } else {
                    inCodeFence = false
                    let joined = fenceLines.joined(separator: "\n")
                    if fenceLang == "mermaid" {
                        html.append("<div class=\"mermaid\">\(escapeHTML(joined))</div>")
                    } else {
                        html.append("<pre><code>\(escapeHTML(joined))</code></pre>")
                    }
                    fenceLang = ""
                    fenceLines = []
                }
                continue
            }

            if inCodeFence {
                fenceLines.append(line)
                continue
            }

            if trimmed.isEmpty {
                closeOpenContainers()
                continue
            }

            // Horizontal rule
            if trimmed == "---" || trimmed == "***" {
                closeOpenContainers()
                html.append("<hr />")
                continue
            }

            // Headings
            if trimmed.hasPrefix("#### ") {
                closeOpenContainers()
                html.append("<h4>\(formatInline(String(trimmed.dropFirst(5))))</h4>")
                continue
            } else if trimmed.hasPrefix("### ") {
                closeOpenContainers()
                html.append("<h3>\(formatInline(String(trimmed.dropFirst(4))))</h3>")
                continue
            } else if trimmed.hasPrefix("## ") {
                closeOpenContainers()
                html.append("<h2>\(formatInline(String(trimmed.dropFirst(3))))</h2>")
                continue
            } else if trimmed.hasPrefix("# ") {
                closeOpenContainers()
                html.append("<h1>\(formatInline(String(trimmed.dropFirst(2))))</h1>")
                continue
            }

            // Blockquote
            if trimmed.hasPrefix(">") {
                closeOpenContainers()
                let quote = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                html.append("<blockquote>\(formatInline(quote))</blockquote>")
                continue
            }

            // Pipe Tables
            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") {
                if inList {
                    html.append("</ul>")
                    inList = false
                }
                let cells = trimmed.dropFirst().dropLast().split(separator: "|", omittingEmptySubsequences: false).map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                let isSeparator = cells.allSatisfy { $0.allSatisfy { $0 == "-" || $0 == ":" } && !$0.isEmpty }
                if isSeparator {
                    continue
                }
                if !inTable {
                    inTable = true
                    let ths = cells.map { "<th>\(formatInline($0))</th>" }.joined()
                    html.append("<table><thead><tr>\(ths)</tr></thead><tbody>")
                } else {
                    let tds = cells.map { "<td>\(formatInline($0))</td>" }.joined()
                    html.append("<tr>\(tds)</tr>")
                }
                continue
            } else if inTable {
                html.append("</tbody></table>")
                inTable = false
            }

            // Bullet list
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                if !inList {
                    inList = true
                    html.append("<ul>")
                }
                html.append("<li>\(formatInline(String(trimmed.dropFirst(2))))</li>")
                continue
            }

            closeOpenContainers()
            html.append("<p>\(formatInline(trimmed))</p>")
        }

        if inCodeFence {
            html.append("<pre><code>\(escapeHTML(fenceLines.joined(separator: "\n")))</code></pre>")
        }
        closeOpenContainers()
        return html.joined(separator: "\n")
    }
}
