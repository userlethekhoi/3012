import Foundation
import Runestone
import TreeSitterHTMLRunestone
import TreeSitterCSSRunestone
import TreeSitterJavaScriptRunestone
import TreeSitterTypeScriptRunestone
import TreeSitterJSONRunestone
import TreeSitterPythonRunestone
import TreeSitterCRunestone
import TreeSitterCPPRunestone
import TreeSitterObjectiveCRunestone
import TreeSitterSwiftRunestone
import TreeSitterMarkdownRunestone
import TreeSitterBashRunestone

public enum CodeLanguage: String, CaseIterable, Identifiable, Codable {
    case html = "HTML"
    case css = "CSS"
    case javascript = "JavaScript"
    case typescript = "TypeScript"
    case json = "JSON"
    case python = "Python"
    case c = "C"
    case cpp = "C++"
    case objectiveC = "Objective-C"
    case swift = "Swift"
    case markdown = "Markdown"
    case shell = "Shell"
    case plainText = "Plain Text"

    public var id: String { rawValue }

    public var defaultExtension: String {
        switch self {
        case .html: return "html"
        case .css: return "css"
        case .javascript: return "js"
        case .typescript: return "ts"
        case .json: return "json"
        case .python: return "py"
        case .c: return "c"
        case .cpp: return "cpp"
        case .objectiveC: return "m"
        case .swift: return "swift"
        case .markdown: return "md"
        case .shell: return "sh"
        case .plainText: return "txt"
        }
    }

    public var systemIcon: String {
        switch self {
        case .html: return "chevron.left.forwardslash.chevron.right"
        case .css: return "curlybraces"
        case .javascript, .typescript: return "curlybraces.square"
        case .json: return "ellipsis.curlybraces"
        case .python: return "terminal"
        case .c, .cpp, .objectiveC: return "cpu"
        case .swift: return "swift"
        case .markdown: return "doc.plaintext"
        case .shell: return "terminal"
        case .plainText: return "doc.text"
        }
    }

    public var lineCommentPrefix: String {
        switch self {
        case .python, .shell: return "# "
        case .html, .markdown: return "<!-- "
        case .css: return "/* "
        default: return "// "
        }
    }

    public var treeSitterLanguage: TreeSitterLanguage? {
        switch self {
        case .html: return .html
        case .css: return .css
        case .javascript: return .javaScript
        case .typescript: return .typeScript
        case .json: return .json
        case .python: return .python
        case .c: return .c
        case .cpp: return .cpp
        case .objectiveC: return .objectiveC
        case .swift: return .swift
        case .markdown: return .markdown
        case .shell: return .bash
        case .plainText: return nil
        }
    }

    public static func detect(from url: URL) -> CodeLanguage {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "html", "htm": return .html
        case "css", "scss": return .css
        case "js", "mjs", "cjs", "jsx": return .javascript
        case "ts", "tsx": return .typescript
        case "json": return .json
        case "py", "pyw": return .python
        case "c", "h": return .c
        case "cpp", "cc", "cxx", "hpp", "hxx": return .cpp
        case "m", "mm": return .objectiveC
        case "swift": return .swift
        case "md", "markdown": return .markdown
        case "sh", "bash", "zsh": return .shell
        default: return .plainText
        }
    }

    public var starterTemplate: String {
        switch self {
        case .html:
            return """
            <!DOCTYPE html>
            <html lang="en">
            <head>
              <meta charset="UTF-8" />
              <meta name="viewport" content="width=device-width, initial-scale=1.0" />
              <title>3012 Live Web App</title>
              <link rel="stylesheet" href="style.css" />
            </head>
            <body>
              <main class="card">
                <h1>Built on iPhone with 3012</h1>
                <p>Edit this file and watch Safari or Split Preview hot-reload instantly.</p>
                <button id="actionBtn">Tap Me</button>
              </main>
              <script src="app.js"></script>
            </body>
            </html>
            """
        case .css:
            return """
            body {
              margin: 0;
              font-family: -apple-system, BlinkMacSystemFont, sans-serif;
              background: #0f172a;
              color: #f8fafc;
              display: grid;
              place-items: center;
              min-height: 100vh;
            }
            .card {
              background: #1e293b;
              padding: 2rem;
              border-radius: 16px;
              text-align: center;
            }
            """
        case .javascript:
            return """
            console.log("Hello from 3012 JS Engine!");
            const nums = [1, 2, 3, 4, 5];
            const sum = nums.reduce((acc, n) => acc + n, 0);
            console.log("Sum:", sum);
            """
        case .typescript:
            return """
            interface Developer {
              name: string;
              ide: string;
            }
            const dev: Developer = { name: "Mobile Dev", ide: "3012" };
            console.log(`${dev.name} coding on ${dev.ide}`);
            """
        case .json:
            return """
            {
              "name": "3012-project",
              "version": "1.0.0"
            }
            """
        case .python:
            return """
            import sys

            def main():
                print(f"Python {sys.version.split()[0]} running from 3012 Mobile IDE!")
                squares = [x * x for x in range(1, 6)]
                print("Squares:", squares)

            if __name__ == "__main__":
                main()
            """
        case .c:
            return """
            #include <stdio.h>

            int main(void) {
                printf("Hello from C17 in 3012 Mobile IDE!\\n");
                return 0;
            }
            """
        case .cpp:
            return """
            #include <iostream>
            #include <vector>
            #include <numeric>

            int main() {
                std::vector<int> values = {10, 20, 30, 40};
                int total = std::accumulate(values.begin(), values.end(), 0);
                std::cout << "C++20 Zero-Config Runner | Total = " << total << "\\n";
                return 0;
            }
            """
        case .objectiveC:
            return """
            #import <Foundation/Foundation.h>

            int main(int argc, const char * argv[]) {
                @autoreleasepool {
                    NSLog(@"Hello Objective-C from 3012!");
                }
                return 0;
            }
            """
        case .swift:
            return """
            import Foundation

            struct Greeting {
                let app = "3012 Mobile IDE"
                func run() {
                    print("Swift running smoothly from \\(app)!")
                }
            }

            Greeting().run()
            """
        case .markdown:
            return """
            # Project Notes

            Created in **3012 Mobile IDE**.
            """
        case .shell:
            return """
            #!/usr/bin/env bash
            echo "Running shell script from 3012..."
            uname -a
            """
        case .plainText:
            return ""
        }
    }
}

public struct FileNode: Identifiable, Hashable {
    public let id: String
    public let url: URL
    public let name: String
    public let isDirectory: Bool
    public var children: [FileNode]?

    public var language: CodeLanguage {
        CodeLanguage.detect(from: url)
    }

    public init(url: URL, isDirectory: Bool, children: [FileNode]? = nil) {
        self.id = url.path
        self.url = url
        self.name = url.lastPathComponent
        self.isDirectory = isDirectory
        self.children = children
    }
}

public struct OpenTab: Identifiable, Equatable {
    public let id: URL
    public var fileURL: URL
    public var content: String
    public var savedContent: String
    public var selectedRangeLocation: Int = 0
    public var selectedRangeLength: Int = 0

    public var title: String { fileURL.lastPathComponent }
    public var isDirty: Bool { content != savedContent }
    public var language: CodeLanguage { CodeLanguage.detect(from: fileURL) }

    public init(fileURL: URL, content: String) {
        self.id = fileURL
        self.fileURL = fileURL
        self.content = content
        self.savedContent = content
    }
}

public struct BasicPair: CharacterPair {
    public let leading: String
    public let trailing: String

    public init(leading: String, trailing: String) {
        self.leading = leading
        self.trailing = trailing
    }

    public static let defaultPairs: [CharacterPair] = [
        BasicPair(leading: "{", trailing: "}"),
        BasicPair(leading: "(", trailing: ")"),
        BasicPair(leading: "[", trailing: "]"),
        BasicPair(leading: "\"", trailing: "\""),
        BasicPair(leading: "'", trailing: "'"),
        BasicPair(leading: "`", trailing: "`")
    ]
}
