import SwiftUI
import UIKit
import Runestone

public struct CompletionReplacementRequest: Equatable {
    public let token: Int
    public let range: NSRange
    public let replacement: String

    public init(token: Int, range: NSRange, replacement: String) {
        self.token = token
        self.range = range
        self.replacement = replacement
    }
}

public struct JumpToLineRequest: Equatable {
    public let token: Int
    public let line: Int // 1-based line number

    public init(token: Int, line: Int) {
        self.token = token
        self.line = line
    }
}

public struct RunestoneEditorView: UIViewRepresentable {
    public let fileURL: URL
    public let text: String
    public let language: CodeLanguage
    @ObservedObject public var preferences: EditorPreferences
    public var highlightedRanges: [HighlightedRange]
    public var completionRequest: CompletionReplacementRequest?
    public var jumpRequest: JumpToLineRequest?
    public var findTriggerToken: Int
    public var toggleCommentToken: Int
    public var onAcceptPrimaryCompletion: () -> Bool
    public var onTextChange: (String, NSRange) -> Void
    public var onSelectionChange: (NSRange) -> Void
    public var onToggleAI: () -> Void

    public init(
        fileURL: URL,
        text: String,
        language: CodeLanguage,
        preferences: EditorPreferences,
        highlightedRanges: [HighlightedRange] = [],
        completionRequest: CompletionReplacementRequest? = nil,
        jumpRequest: JumpToLineRequest? = nil,
        findTriggerToken: Int,
        toggleCommentToken: Int = 0,
        onAcceptPrimaryCompletion: @escaping () -> Bool = { false },
        onTextChange: @escaping (String, NSRange) -> Void,
        onSelectionChange: @escaping (NSRange) -> Void,
        onToggleAI: @escaping () -> Void
    ) {
        self.fileURL = fileURL
        self.text = text
        self.language = language
        self.preferences = preferences
        self.highlightedRanges = highlightedRanges
        self.completionRequest = completionRequest
        self.jumpRequest = jumpRequest
        self.findTriggerToken = findTriggerToken
        self.toggleCommentToken = toggleCommentToken
        self.onAcceptPrimaryCompletion = onAcceptPrimaryCompletion
        self.onTextChange = onTextChange
        self.onSelectionChange = onSelectionChange
        self.onToggleAI = onToggleAI
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public func makeUIView(context: Context) -> TextView {
        let textView = TextView()
        textView.editorDelegate = context.coordinator
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
        textView.spellCheckingType = .no
        textView.isFindInteractionEnabled = true
        textView.lineSelectionDisplayType = .line
        textView.characterPairs = BasicPair.defaultPairs
        textView.characterPairTrailingComponentDeletionMode = .immediatelyFollowingLeadingComponent
        textView.verticalOverscrollFactor = 0.35
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 6, bottom: 52, right: 10)

        let coord = context.coordinator
        let prefs = preferences
        let codingBar = ProCodingAccessoryBar()
        codingBar.targetTextView = textView
        codingBar.tabWidthProvider = { [weak prefs] in prefs?.tabWidth ?? 2 }
        codingBar.commentPrefixProvider = { [weak coord] in
            coord?.parent.language.lineCommentPrefix ?? "// "
        }
        codingBar.onAcceptPrimaryCompletion = { [weak coord] in
            coord?.parent.onAcceptPrimaryCompletion() ?? false
        }
        codingBar.onTriggerAI = { [weak coord] in
            coord?.parent.onToggleAI()
        }
        codingBar.onTriggerFind = { [weak textView] in
            textView?.findInteraction?.presentFindNavigator(showingReplace: true)
        }
        textView.inputAccessoryView = codingBar

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        textView.addGestureRecognizer(pinch)

        applyAppearance(to: textView)
        context.coordinator.loadState(into: textView, fileURL: fileURL, code: text, language: language, theme: preferences.makeRunestoneTheme())
        return textView
    }

    public func updateUIView(_ textView: TextView, context: Context) {
        context.coordinator.parent = self
        applyAppearance(to: textView)

        let signature = "\(preferences.themeSignature)|\(preferences.fontName)|\(Int(preferences.fontSize * 2))"
        let fileChanged = context.coordinator.loadedFileURL != fileURL
        let themeChanged = context.coordinator.loadedAppearanceSignature != signature

        // 1. Apply Autocomplete Replacement cleanly via Runestone's Undo-safe replace(_:withText:)
        if let comp = completionRequest, comp.token != context.coordinator.lastCompletionToken {
            context.coordinator.lastCompletionToken = comp.token
            let totalLen = (textView.text as NSString).length
            let safeLoc = min(max(0, comp.range.location), totalLen)
            let safeLen = min(max(0, comp.range.length), totalLen - safeLoc)
            context.coordinator.isInternalEdit = true
            textView.replace(NSRange(location: safeLoc, length: safeLen), withText: comp.replacement)
            onTextChange(textView.text, textView.selectedRange)
            DispatchQueue.main.async {
                context.coordinator.isInternalEdit = false
            }
            return
        }

        // 2. Toggle Line Comment (Cmd+/ or Command Palette)
        if context.coordinator.lastToggleCommentToken != toggleCommentToken {
            context.coordinator.lastToggleCommentToken = toggleCommentToken
            toggleLineComment(in: textView)
            return
        }

        let externalTextChanged = (!context.coordinator.isInternalEdit && textView.text != text)

        if fileChanged || themeChanged || externalTextChanged {
            let preservedRange = textView.selectedRange
            context.coordinator.loadState(
                into: textView,
                fileURL: fileURL,
                code: text,
                language: language,
                theme: preferences.makeRunestoneTheme(),
                restoreSelection: fileChanged ? nil : preservedRange
            )
            context.coordinator.loadedAppearanceSignature = signature
        }

        // 3. Apply Inline Error / Warning Highlighted Ranges
        if textView.highlightedRanges != highlightedRanges {
            let docLen = (textView.text as NSString).length
            let clamped = highlightedRanges.compactMap { hr -> HighlightedRange? in
                guard hr.range.location >= 0, hr.range.location + hr.range.length <= docLen, hr.range.length > 0 else {
                    return nil
                }
                return hr
            }
            if textView.highlightedRanges != clamped {
                textView.highlightedRanges = clamped
            }
        }

        // 4. Jump to Line (Outline / Problems / Breadcrumb)
        if let jump = jumpRequest, jump.token != context.coordinator.lastJumpToken {
            context.coordinator.lastJumpToken = jump.token
            let zeroBased = max(0, jump.line - 1)
            _ = textView.goToLine(zeroBased, select: .line)
            if !textView.isFirstResponder {
                textView.becomeFirstResponder()
            }
        }

        // 5. Native Find & Replace Navigator
        if context.coordinator.lastFindToken != findTriggerToken {
            context.coordinator.lastFindToken = findTriggerToken
            textView.findInteraction?.presentFindNavigator(showingReplace: true)
        }
    }

    private func applyAppearance(to textView: TextView) {
        let palette = preferences.activePalette
        textView.backgroundColor = UIColor(hexString: palette.editorBackground)
        textView.insertionPointColor = UIColor(hexString: palette.accent)
        textView.selectionBarColor = UIColor(hexString: palette.accent)
        textView.selectionHighlightColor = UIColor(hexString: palette.selectionBackground).withAlphaComponent(0.55)
        textView.keyboardAppearance = palette.isDark ? .dark : .light
        textView.showLineNumbers = preferences.showLineNumbers
        textView.isLineWrappingEnabled = preferences.wordWrap
        textView.isCodeFoldingEnabled = preferences.enableCodeFolding
        textView.showSpaces = preferences.showInvisibleCharacters
        textView.showTabs = preferences.showInvisibleCharacters
        textView.lineHeightMultiplier = CGFloat(preferences.lineHeightMultiplier)
        textView.indentStrategy = .space(length: preferences.tabWidth)
    }

    private func toggleLineComment(in textView: TextView) {
        guard language != .html && language != .css && language != .markdown else { return }
        let prefix = language.lineCommentPrefix
        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespaces)
        let ns = textView.text as NSString
        guard ns.length > 0 else { return }
        let lineRange = ns.lineRange(for: textView.selectedRange)
        let block = ns.substring(with: lineRange)
        let hasTrailingNewline = block.hasSuffix("\n")
        var lines = block.components(separatedBy: "\n")
        if hasTrailingNewline && lines.last == "" {
            lines.removeLast()
        }
        let allCommented = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .allSatisfy { $0.trimmingCharacters(in: .whitespaces).hasPrefix(trimmedPrefix) }

        let transformed = lines.map { line -> String in
            if allCommented {
                if let r = line.range(of: prefix) {
                    var copy = line
                    copy.removeSubrange(r)
                    return copy
                } else if let r2 = line.range(of: trimmedPrefix) {
                    var copy = line
                    copy.removeSubrange(r2)
                    return copy
                }
                return line
            } else {
                return prefix + line
            }
        }
        let replacement = transformed.joined(separator: "\n") + (hasTrailingNewline ? "\n" : "")
        textView.replace(lineRange, withText: replacement)
        onTextChange(textView.text, textView.selectedRange)
    }

    public final class Coordinator: NSObject, TextViewDelegate {
        var parent: RunestoneEditorView
        var loadedFileURL: URL?
        var loadedAppearanceSignature: String = ""
        var isInternalEdit: Bool = false
        var lastFindToken: Int = 0
        var lastCompletionToken: Int = 0
        var lastJumpToken: Int = 0
        var lastToggleCommentToken: Int = 0
        private var pinchStartFontSize: CGFloat = 14.0

        init(parent: RunestoneEditorView) {
            self.parent = parent
            self.lastFindToken = parent.findTriggerToken
            self.lastToggleCommentToken = parent.toggleCommentToken
            self.lastCompletionToken = parent.completionRequest?.token ?? 0
            self.lastJumpToken = parent.jumpRequest?.token ?? 0
        }

        func loadState(
            into textView: TextView,
            fileURL: URL,
            code: String,
            language: CodeLanguage,
            theme: IDERunestoneTheme,
            restoreSelection: NSRange? = nil
        ) {
            self.loadedFileURL = fileURL
            let tsLanguage = language.treeSitterLanguage
            DispatchQueue.global(qos: .userInitiated).async {
                let state: TextViewState
                if let tsLanguage {
                    state = TextViewState(text: code, theme: theme, language: tsLanguage)
                } else {
                    state = TextViewState(text: code, theme: theme)
                }
                DispatchQueue.main.async { [weak self, weak textView] in
                    guard let self, let textView, self.loadedFileURL == fileURL else { return }
                    textView.setState(state)
                    if let sel = restoreSelection, sel.location + sel.length <= (code as NSString).length {
                        textView.selectedRange = sel
                    }
                    let docLen = (textView.text as NSString).length
                    textView.highlightedRanges = self.parent.highlightedRanges.filter {
                        $0.range.location >= 0 && $0.range.location + $0.range.length <= docLen && $0.range.length > 0
                    }
                }
            }
        }

        public func textViewDidChange(_ textView: TextView) {
            isInternalEdit = true
            parent.onTextChange(textView.text, textView.selectedRange)
            DispatchQueue.main.async { [weak self] in
                self?.isInternalEdit = false
            }
        }

        public func textViewDidChangeSelection(_ textView: TextView) {
            parent.onSelectionChange(textView.selectedRange)
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                pinchStartFontSize = parent.preferences.fontSize
            case .changed:
                let updated = round(pinchStartFontSize * gesture.scale * 2.0) / 2.0
                let clamped = min(max(updated, 10.0), 28.0)
                if abs(parent.preferences.fontSize - clamped) >= 0.5 {
                    parent.preferences.fontSize = clamped
                }
            default:
                break
            }
        }
    }
}
