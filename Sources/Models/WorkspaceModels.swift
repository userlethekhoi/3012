import Foundation
import Runestone
import TreeSitterAstroRunestone
import TreeSitterBashRunestone
import TreeSitterBicepRunestone
import TreeSitterCMakeRunestone
import TreeSitterCPPRunestone
import TreeSitterCRunestone
import TreeSitterCSharpRunestone
import TreeSitterCSSRunestone
import TreeSitterDartRunestone
import TreeSitterDiffRunestone
import TreeSitterElixirRunestone
import TreeSitterElmRunestone
import TreeSitterFishRunestone
import TreeSitterGoRunestone
import TreeSitterHCLRunestone
import TreeSitterHTMLRunestone
import TreeSitterHaskellRunestone
import TreeSitterJSON5Runestone
import TreeSitterJSONRunestone
import TreeSitterJavaRunestone
import TreeSitterJavaScriptRunestone
import TreeSitterJuliaRunestone
import TreeSitterLaTeXRunestone
import TreeSitterLuaRunestone
import TreeSitterMarkdownInlineRunestone
import TreeSitterMarkdownRunestone
import TreeSitterNixRunestone
import TreeSitterOCamlRunestone
import TreeSitterObjectiveCRunestone
import TreeSitterPHPRunestone
import TreeSitterPascalRunestone
import TreeSitterPerlRunestone
import TreeSitterProtoRunestone
import TreeSitterPythonRunestone
import TreeSitterRRunestone
import TreeSitterRegexRunestone
import TreeSitterRubyRunestone
import TreeSitterRustRunestone
import TreeSitterSCSSRunestone
import TreeSitterSQLRunestone
import TreeSitterScalaRunestone
import TreeSitterSvelteRunestone
import TreeSitterSwiftRunestone
import TreeSitterTOMLRunestone
import TreeSitterTSXRunestone
import TreeSitterTypeScriptRunestone
import TreeSitterXMLRunestone
import TreeSitterYAMLRunestone

public enum CodeLanguage: String, CaseIterable, Identifiable, Codable {
    // Web & Frontend
    case html = "HTML"
    case css = "CSS"
    case scss = "SCSS"
    case javascript = "JavaScript"
    case typescript = "TypeScript"
    case tsx = "TypeScript React (TSX)"
    case vue = "Vue"
    case svelte = "Svelte"
    case astro = "Astro"
    case graphql = "GraphQL"

    // Systems & Native
    case c = "C"
    case cpp = "C++"
    case objectiveC = "Objective-C"
    case rust = "Rust"
    case go = "Go"
    case zig = "Zig"
    case dlang = "D"
    case nim = "Nim"
    case crystal = "Crystal"
    case assembly = "Assembly"

    // JVM, .NET & Mobile
    case swift = "Swift"
    case dart = "Dart"
    case java = "Java"
    case kotlin = "Kotlin"
    case scala = "Scala"
    case groovy = "Groovy"
    case csharp = "C#"

    // Scripting & Dynamic
    case python = "Python"
    case php = "PHP"
    case ruby = "Ruby"
    case perl = "Perl"
    case lua = "Lua"

    // Data Science, Functional & Smart Contracts
    case r = "R"
    case julia = "Julia"
    case elixir = "Elixir"
    case erlang = "Erlang"
    case haskell = "Haskell"
    case ocaml = "OCaml"
    case elm = "Elm"
    case lisp = "Lisp"
    case pascal = "Pascal"
    case solidity = "Solidity"

    // Database, Config & Serialization
    case sql = "SQL"
    case json = "JSON"
    case json5 = "JSON5"
    case yaml = "YAML"
    case toml = "TOML"
    case xml = "XML"
    case protobuf = "Protocol Buffers"
    case ini = "INI / Env"

    // DevOps, Build & Shell
    case shell = "Shell (Bash/Zsh)"
    case fish = "Fish Shell"
    case powershell = "PowerShell"
    case dockerfile = "Dockerfile"
    case makefile = "Makefile"
    case cmake = "CMake"
    case hcl = "Terraform / HCL"
    case bicep = "Bicep"
    case nix = "Nix"

    // Docs, Markup & Diff
    case markdown = "Markdown"
    case latex = "LaTeX"
    case regex = "Regex"
    case diff = "Diff / Patch"
    case plainText = "Plain Text"

    public var id: String { rawValue }

    public var shortBadgeName: String {
        switch self {
        case .tsx: return "TSX"
        case .typescript: return "TS"
        case .javascript: return "JS"
        case .objectiveC: return "Obj-C"
        case .protobuf: return "Proto"
        case .shell: return "Bash"
        case .fish: return "Fish"
        case .powershell: return "PS1"
        case .hcl: return "HCL/TF"
        case .ini: return "INI/Env"
        case .diff: return "Diff"
        default: return rawValue
        }
    }

    public var defaultExtension: String {
        switch self {
        case .html: return "html"
        case .css: return "css"
        case .scss: return "scss"
        case .javascript: return "js"
        case .typescript: return "ts"
        case .tsx: return "tsx"
        case .vue: return "vue"
        case .svelte: return "svelte"
        case .astro: return "astro"
        case .graphql: return "graphql"
        case .c: return "c"
        case .cpp: return "cpp"
        case .objectiveC: return "m"
        case .rust: return "rs"
        case .go: return "go"
        case .zig: return "zig"
        case .dlang: return "d"
        case .nim: return "nim"
        case .crystal: return "cr"
        case .assembly: return "asm"
        case .swift: return "swift"
        case .dart: return "dart"
        case .java: return "java"
        case .kotlin: return "kt"
        case .scala: return "scala"
        case .groovy: return "groovy"
        case .csharp: return "cs"
        case .python: return "py"
        case .php: return "php"
        case .ruby: return "rb"
        case .perl: return "pl"
        case .lua: return "lua"
        case .r: return "R"
        case .julia: return "jl"
        case .elixir: return "ex"
        case .erlang: return "erl"
        case .haskell: return "hs"
        case .ocaml: return "ml"
        case .elm: return "elm"
        case .lisp: return "lisp"
        case .pascal: return "pas"
        case .solidity: return "sol"
        case .sql: return "sql"
        case .json: return "json"
        case .json5: return "json5"
        case .yaml: return "yaml"
        case .toml: return "toml"
        case .xml: return "xml"
        case .protobuf: return "proto"
        case .ini: return "ini"
        case .shell: return "sh"
        case .fish: return "fish"
        case .powershell: return "ps1"
        case .dockerfile: return "Dockerfile"
        case .makefile: return "Makefile"
        case .cmake: return "cmake"
        case .hcl: return "tf"
        case .bicep: return "bicep"
        case .nix: return "nix"
        case .markdown: return "md"
        case .latex: return "tex"
        case .regex: return "regex"
        case .diff: return "diff"
        case .plainText: return "txt"
        }
    }

    public var systemIcon: String {
        switch self {
        case .html, .vue, .svelte, .astro, .xml:
            return "chevron.left.forwardslash.chevron.right"
        case .css, .scss:
            return "curlybraces"
        case .javascript, .typescript, .tsx, .graphql:
            return "curlybraces.square"
        case .json, .json5, .yaml, .toml, .ini, .protobuf:
            return "ellipsis.curlybraces"
        case .python, .ruby, .perl, .lua, .php:
            return "terminal"
        case .c, .cpp, .objectiveC, .rust, .zig, .dlang, .assembly:
            return "cpu"
        case .go, .hcl, .bicep, .dockerfile, .nix:
            return "server.rack"
        case .java, .kotlin, .scala, .groovy, .csharp, .dart, .solidity:
            return "cube"
        case .swift:
            return "swift"
        case .r, .julia, .elixir, .erlang, .haskell, .ocaml, .elm, .lisp, .pascal, .nim, .crystal:
            return "function"
        case .sql:
            return "cylinder.split.1x2"
        case .shell, .fish, .powershell, .makefile, .cmake:
            return "apple.terminal"
        case .markdown, .latex:
            return "doc.plaintext"
        case .diff:
            return "arrow.left.arrow.right"
        case .regex:
            return "asterisk"
        case .plainText:
            return "doc.text"
        }
    }

    public var lineCommentPrefix: String {
        switch self {
        case .python, .ruby, .perl, .r, .julia, .elixir, .nim, .crystal, .yaml, .toml, .ini,
             .shell, .fish, .powershell, .dockerfile, .makefile, .cmake, .hcl, .nix, .graphql:
            return "# "
        case .lua, .sql, .haskell, .elm:
            return "-- "
        case .erlang, .latex:
            return "% "
        case .lisp, .assembly:
            return "; "
        case .ocaml:
            return "(* "
        case .html, .xml, .vue, .svelte, .markdown:
            return "<!-- "
        case .css:
            return "/* "
        default:
            return "// "
        }
    }

    public var treeSitterLanguage: TreeSitterLanguage? {
        switch self {
        case .html, .vue: return .html
        case .css: return .css
        case .scss: return .scss
        case .javascript: return .javaScript
        case .typescript, .graphql: return .typeScript
        case .tsx: return .tsx
        case .svelte: return .svelte
        case .astro: return .astro
        case .c, .assembly: return .c
        case .cpp: return .cpp
        case .objectiveC: return .objectiveC
        case .rust, .zig: return .rust
        case .go: return .go
        case .dlang: return .cpp
        case .nim: return .python
        case .crystal, .ruby: return .ruby
        case .swift: return .swift
        case .dart: return .dart
        case .java, .kotlin, .groovy: return .java
        case .scala: return .scala
        case .csharp, .solidity: return .cSharp
        case .python: return .python
        case .php: return .php
        case .perl: return .perl
        case .lua: return .lua
        case .r: return .r
        case .julia: return .julia
        case .elixir, .erlang: return .elixir
        case .haskell: return .haskell
        case .ocaml: return .ocaml
        case .elm: return .elm
        case .lisp: return .clojureOrFallback
        case .pascal: return .pascal
        case .sql: return .sql
        case .json: return .json
        case .json5: return .json5
        case .yaml: return .yaml
        case .toml, .ini: return .toml
        case .xml: return .xml
        case .protobuf: return .proto
        case .shell, .powershell, .dockerfile, .makefile: return .bash
        case .fish: return .fish
        case .cmake: return .cmake
        case .hcl: return .hcl
        case .bicep: return .bicep
        case .nix: return .nix
        case .markdown: return .markdown
        case .latex: return .latex
        case .regex: return .regex
        case .diff: return .diff
        case .plainText: return nil
        }
    }

    // MARK: - 3-Layer Universal Language Detector (Filename + 145+ Extensions + Shebang & Content Sniffing)
    public static func detect(from url: URL, contentSample: String? = nil) -> CodeLanguage {
        let filename = url.lastPathComponent
        let lowerName = filename.lowercased()
        let ext = url.pathExtension.lowercased()

        // Layer 1: Exact Special Filenames
        if lowerName == "dockerfile" || lowerName.hasPrefix("dockerfile.") || lowerName == "containerfile" {
            return .dockerfile
        }
        if lowerName == "makefile" || lowerName == "gnumakefile" || lowerName == "justfile" {
            return .makefile
        }
        if lowerName == "cmakelists.txt" {
            return .cmake
        }
        if ["gemfile", "rakefile", "podfile", "fastfile", "appfile", "vagrantfile", "brewfile"].contains(lowerName) {
            return .ruby
        }
        if lowerName.hasPrefix(".env") || [".editorconfig", ".gitconfig", ".npmrc", "nginx.conf"].contains(lowerName) {
            return .ini
        }
        if [".bashrc", ".zshrc", ".bash_profile", ".zprofile", ".profile"].contains(lowerName) {
            return .shell
        }
        if [".prettierrc", ".eslintrc", ".babelrc", "tsconfig.json", "jsconfig.json", "composer.lock", "package.json"].contains(lowerName) {
            return .json
        }
        if lowerName == "cargo.lock" {
            return .toml
        }

        // Layer 2: Comprehensive File Extension Mapping (145+ extensions)
        switch ext {
        case "html", "htm", "xhtml", "ejs", "hbs", "mustache", "twig": return .html
        case "css", "less", "pcss": return .css
        case "scss", "sass": return .scss
        case "js", "mjs", "cjs", "jsx": return .javascript
        case "ts", "mts", "cts": return .typescript
        case "tsx": return .tsx
        case "vue": return .vue
        case "svelte": return .svelte
        case "astro": return .astro
        case "graphql", "gql": return .graphql

        case "c", "h": return .c
        case "cpp", "cc", "cxx", "c++", "hpp", "hh", "hxx", "h++", "ipp", "tpp", "ino", "cu", "cuh": return .cpp
        case "m", "mm": return .objectiveC
        case "rs": return .rust
        case "go": return .go
        case "zig", "zon": return .zig
        case "d", "di": return .dlang
        case "nim", "nims": return .nim
        case "cr": return .crystal
        case "asm", "s", "nasm": return .assembly

        case "swift": return .swift
        case "dart": return .dart
        case "java", "jav": return .java
        case "kt", "kts": return .kotlin
        case "scala", "sc", "sbt": return .scala
        case "groovy", "gradle", "gvy": return .groovy
        case "cs", "csx": return .csharp

        case "py", "pyw", "pyi", "ipynb": return .python
        case "php", "phtml", "php8": return .php
        case "rb", "erb", "gemspec", "ru": return .ruby
        case "pl", "pm", "t": return .perl
        case "lua", "luau": return .lua

        case "r", "rmd": return .r
        case "jl": return .julia
        case "ex", "exs", "heex": return .elixir
        case "erl", "hrl": return .erlang
        case "hs", "lhs": return .haskell
        case "ml", "mli", "ocaml": return .ocaml
        case "elm": return .elm
        case "lisp", "cl", "el", "scm", "rkt", "clj", "cljs": return .lisp
        case "pas", "pp", "dpr", "lpr": return .pascal
        case "sol": return .solidity

        case "sql", "psql", "mysql", "sqlite", "prisma": return .sql
        case "json", "jsonc", "geojson", "arb": return .json
        case "json5": return .json5
        case "yaml", "yml": return .yaml
        case "toml": return .toml
        case "xml", "svg", "plist", "csproj", "fsproj", "vbproj", "xaml", "AndroidManifest": return .xml
        case "proto": return .protobuf
        case "ini", "cfg", "conf", "properties", "env": return .ini

        case "sh", "bash", "zsh", "ksh", "command": return .shell
        case "fish": return .fish
        case "ps1", "psm1", "psd1": return .powershell
        case "dockerfile": return .dockerfile
        case "mk", "mak", "make": return .makefile
        case "cmake": return .cmake
        case "tf", "tfvars", "hcl", "nomad": return .hcl
        case "bicep": return .bicep
        case "nix": return .nix

        case "md", "markdown", "mdx": return .markdown
        case "tex", "sty", "cls", "bib": return .latex
        case "regex": return .regex
        case "diff", "patch": return .diff
        default: break
        }

        // Layer 3: Shebang & Content Signature Sniffing (when extensionless or unknown)
        let sample: String? = contentSample ?? (try? String(contentsOf: url, encoding: .utf8)).map { String($0.prefix(1200)) }
        if let sample {
            if let detected = sniffContentLanguage(sample) {
                return detected
            }
        }
        return .plainText
    }

    public static func sniffContentLanguage(_ sample: String) -> CodeLanguage? {
        let trimmed = sample.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let firstLine = trimmed.components(separatedBy: "\n").first?.lowercased() ?? ""

        // 1. Shebang (#!...)
        if firstLine.hasPrefix("#!") {
            if firstLine.contains("python") { return .python }
            if firstLine.contains("node") || firstLine.contains("deno") || firstLine.contains("bun") { return .javascript }
            if firstLine.contains("ts-node") || firstLine.contains("tsx") { return .typescript }
            if firstLine.contains("fish") { return .fish }
            if firstLine.contains("pwsh") || firstLine.contains("powershell") { return .powershell }
            if firstLine.contains("ruby") { return .ruby }
            if firstLine.contains("perl") { return .perl }
            if firstLine.contains("php") { return .php }
            if firstLine.contains("lua") { return .lua }
            if firstLine.contains("elixir") { return .elixir }
            if firstLine.contains("julia") { return .julia }
            if firstLine.contains("rscript") { return .r }
            if firstLine.contains("sh") || firstLine.contains("bash") || firstLine.contains("zsh") { return .shell }
        }

        // 2. Structural Signatures
        let lowerPrefix = String(trimmed.prefix(500)).lowercased()
        if lowerPrefix.hasPrefix("<!doctype html") || lowerPrefix.hasPrefix("<html") { return .html }
        if lowerPrefix.hasPrefix("<?xml") || lowerPrefix.hasPrefix("<svg") { return .xml }
        if lowerPrefix.hasPrefix("<?php") { return .php }
        if (trimmed.hasPrefix("{") || trimmed.hasPrefix("[")) && trimmed.contains("\":") { return .json }
        if trimmed.contains("#include <iostream>") || trimmed.contains("std::") || trimmed.contains("using namespace std") { return .cpp }
        if trimmed.contains("#include <stdio.h>") || trimmed.contains("#include <stdlib.h>") { return .c }
        if trimmed.hasPrefix("package main") && trimmed.contains("func ") { return .go }
        if trimmed.contains("fn main()") && (trimmed.contains("println!") || trimmed.contains("let mut ")) { return .rust }
        if trimmed.contains("public static void main(String") { return .java }
        if trimmed.contains("fun main(") { return .kotlin }
        if trimmed.contains("using System;") && trimmed.contains("namespace ") { return .csharp }
        if lowerPrefix.hasPrefix("from ") && lowerPrefix.contains("\nrun ") { return .dockerfile }
        if lowerPrefix.hasPrefix("select ") || lowerPrefix.hasPrefix("create table ") || lowerPrefix.hasPrefix("insert into ") { return .sql }
        return nil
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
        case .css, .scss:
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
            """
        case .javascript:
            return """
            console.log("Hello from 3012 JS Engine!");
            const nums = [1, 2, 3, 4, 5];
            console.log("Sum:", nums.reduce((acc, n) => acc + n, 0));
            """
        case .typescript, .tsx:
            return """
            interface Developer {
              name: string;
              ide: string;
            }
            const dev: Developer = { name: "Mobile Dev", ide: "3012" };
            console.log(`${dev.name} coding on ${dev.ide}`);
            """
        case .python:
            return """
            def main() -> None:
                squares = [x * x for x in range(1, 6)]
                print("Python Squares:", squares)


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
                std::cout << "C++20 Total = " << total << "\\n";
                return 0;
            }
            """
        case .rust:
            return """
            fn main() {
                let nums = vec![1, 2, 3, 4, 5];
                let sum: i32 = nums.iter().sum();
                println!("Rust running in 3012 | Sum = {}", sum);
            }
            """
        case .go:
            return """
            package main

            import "fmt"

            func main() {
            \tfmt.Println("Go running in 3012 Mobile IDE!")
            }
            """
        case .java:
            return """
            public class Main {
                public static void main(String[] args) {
                    System.out.println("Java running in 3012 Mobile IDE!");
                }
            }
            """
        case .kotlin:
            return """
            fun main() {
                println("Kotlin in 3012 Mobile IDE!")
            }
            """
        case .csharp:
            return """
            using System;

            class Program {
                static void Main() {
                    Console.WriteLine("C# running in 3012 Mobile IDE!");
                }
            }
            """
        case .dart:
            return """
            void main() {
              print('Dart running in 3012 Mobile IDE!');
            }
            """
        case .php:
            return """
            <?php
            echo "PHP 8 running in 3012 Mobile IDE!\\n";
            """
        case .ruby:
            return """
            puts "Ruby running in 3012 Mobile IDE!"
            """
        case .lua:
            return """
            print("Lua running in 3012 Mobile IDE!")
            """
        case .sql:
            return """
            CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT);
            INSERT INTO users (name) VALUES ('3012 Developer');
            SELECT * FROM users;
            """
        case .swift:
            return """
            import Foundation

            print("Swift running smoothly from 3012 Mobile IDE!")
            """
        case .json, .json5:
            return "{\n  \"name\": \"3012-project\",\n  \"version\": \"1.0.0\"\n}\n"
        case .markdown:
            return "# Project Notes\n\nCreated in **3012 Mobile IDE**.\n"
        case .shell, .fish:
            return "#!/usr/bin/env bash\necho \"Running shell script from 3012...\"\n"
        default:
            return ""
        }
    }
}

private extension TreeSitterLanguage {
    static var clojureOrFallback: TreeSitterLanguage { .bash }
}

// MARK: - VS Code Semantic Working-Tree File Decorations
public enum WorkspaceFileDiffStatus: String, Codable, Equatable, Hashable, Sendable {
    case unchanged
    case untrackedNew  // Brand-new file ("U" — Green)
    case addedCode     // Updated with newly added code lines ("A" — Green)
    case modified      // Edited in-place without adding net new code ("M" — Yellow / Amber)
    case deleted       // Recently deleted file ("D" — Red + strikethrough)

    public var badgeText: String? {
        switch self {
        case .unchanged: return nil
        case .untrackedNew: return "U"
        case .addedCode: return "A"
        case .modified: return "M"
        case .deleted: return "D"
        }
    }

    public var isStrikethrough: Bool {
        self == .deleted
    }

    public var priorityRank: Int {
        switch self {
        case .deleted: return 4
        case .modified: return 3
        case .addedCode: return 2
        case .untrackedNew: return 1
        case .unchanged: return 0
        }
    }

    /// Official VS Code Explorer / Git Decoration Colors (Dark & Light theme adapted)
    public func colorHex(isDark: Bool) -> String? {
        switch self {
        case .unchanged:
            return nil
        case .untrackedNew, .addedCode:
            return isDark ? "#73C991" : "#1A7F37"
        case .modified:
            return isDark ? "#E2C08D" : "#9A6700"
        case .deleted:
            return isDark ? "#F14C4C" : "#CF222E"
        }
    }

    public static func classify(baselineContent: String?, currentContent: String?) -> WorkspaceFileDiffStatus {
        switch (baselineContent, currentContent) {
        case (nil, nil):
            return .unchanged
        case (nil, .some):
            return .untrackedNew
        case (.some, nil):
            return .deleted
        case let (.some(rawOld), .some(rawNew)):
            let old = rawOld.replacingOccurrences(of: "\r\n", with: "\n")
            let new = rawNew.replacingOccurrences(of: "\r\n", with: "\n")
            if old == new {
                return .unchanged
            }
            let oldNonEmpty = old.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            let newNonEmpty = new.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            // Added new code lines (or populated a previously blank file) -> VS Code Green ("A")
            if newNonEmpty.count > oldNonEmpty.count || (oldNonEmpty.isEmpty && !newNonEmpty.isEmpty) {
                return .addedCode
            }
            // In-place code edits / replacements / line removals without adding net new code -> VS Code Amber/Yellow ("M")
            return .modified
        }
    }

    public static func lineDelta(baselineContent: String?, currentContent: String?) -> (added: Int, removed: Int) {
        let oldLines = (baselineContent ?? "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let newLines = (currentContent ?? "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        if baselineContent == nil { return (newLines.count, 0) }
        if currentContent == nil { return (0, oldLines.count) }

        var oldBag: [String: Int] = [:]
        for l in oldLines { oldBag[l, default: 0] += 1 }
        var shared = 0
        for l in newLines {
            if let c = oldBag[l], c > 0 {
                shared += 1
                oldBag[l] = c - 1
            }
        }
        return (max(0, newLines.count - shared), max(0, oldLines.count - shared))
    }
}

public struct FileNode: Identifiable, Hashable {
    public let id: String
    public let url: URL
    public let name: String
    public let isDirectory: Bool
    public let isDeletedGhost: Bool
    public var children: [FileNode]?

    public var language: CodeLanguage {
        CodeLanguage.detect(from: url)
    }

    public init(url: URL, isDirectory: Bool, isDeletedGhost: Bool = false, children: [FileNode]? = nil) {
        self.id = isDeletedGhost ? "deleted::\(url.path)" : url.path
        self.url = url
        self.name = url.lastPathComponent
        self.isDirectory = isDirectory
        self.isDeletedGhost = isDeletedGhost
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
    public var languageOverride: CodeLanguage? = nil

    public var title: String { fileURL.lastPathComponent }
    public var isDirty: Bool { content != savedContent }
    public var language: CodeLanguage {
        if let languageOverride {
            return languageOverride
        }
        return CodeLanguage.detect(from: fileURL, contentSample: String(content.prefix(1200)))
    }

    public init(fileURL: URL, content: String, languageOverride: CodeLanguage? = nil) {
        self.id = fileURL
        self.fileURL = fileURL
        self.content = content
        self.savedContent = content
        self.languageOverride = languageOverride
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
