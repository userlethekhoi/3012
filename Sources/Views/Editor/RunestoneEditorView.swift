import SwiftUI
import UIKit
import Runestone

public struct CompletionReplacementRequest: Equatable {
    public let token: Int
    public let range: NSRange
    public let replacement: String
    public let cursorOffset: Int?

    public init(token: Int, range: NSRange, replacement: String, cursorOffset: Int? = nil) {
        self.token = token
        self.range = range
        self.replacement = replacement
        self.cursorOffset = cursorOffset
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

public enum EditorQuickActionKind: Equatable {
    case undo
    case redo
    case copy
    case paste
    case cut
    case selectAll
    case duplicateLine
    case deleteLine
    case toggleComment
    case moveLineUp
    case moveLineDown
    case moveLeft
    case moveRight
    case moveUp
    case moveDown
    case moveLineStart
    case moveLineEnd
}

public struct SelectRangeRequest: Equatable {
    public let token: Int
    public let range: NSRange

    public init(token: Int, range: NSRange) {
        self.token = token
        self.range = range
    }
}

public struct EditorQuickActionRequest: Equatable {
    public let token: Int
    public let kind: EditorQuickActionKind

    public init(token: Int, kind: EditorQuickActionKind) {
        self.token = token
        self.kind = kind
    }
}

public struct RunestoneEditorView: UIViewRepresentable {
    public let fileURL: URL
    public let text: String
    public let language: CodeLanguage
    @ObservedObject public var preferences: EditorPreferences
    public var highlightedRanges: [HighlightedRange]
    public var ghostSuggestion: CompletionCandidate?
    public var completionRequest: CompletionReplacementRequest?
    public var jumpRequest: JumpToLineRequest?
    public var selectRangeRequest: SelectRangeRequest?
    public var quickActionRequest: EditorQuickActionRequest?
    public var findTriggerToken: Int
    public var toggleCommentToken: Int
    public var onAcceptPrimaryCompletion: () -> Bool
    public var onTextChange: (String, NSRange) -> Void
    public var onSelectionChange: (NSRange) -> Void
    public var onToggleAI: () -> Void
    public var onTriggerGoToLine: () -> Void
    public var onTriggerFindBar: (() -> Void)?

    public init(
        fileURL: URL,
        text: String,
        language: CodeLanguage,
        preferences: EditorPreferences,
        highlightedRanges: [HighlightedRange] = [],
        ghostSuggestion: CompletionCandidate? = nil,
        completionRequest: CompletionReplacementRequest? = nil,
        jumpRequest: JumpToLineRequest? = nil,
        selectRangeRequest: SelectRangeRequest? = nil,
        quickActionRequest: EditorQuickActionRequest? = nil,
        findTriggerToken: Int,
        toggleCommentToken: Int = 0,
        onAcceptPrimaryCompletion: @escaping () -> Bool = { false },
        onTextChange: @escaping (String, NSRange) -> Void,
        onSelectionChange: @escaping (NSRange) -> Void,
        onToggleAI: @escaping () -> Void,
        onTriggerGoToLine: @escaping () -> Void = {},
        onTriggerFindBar: (() -> Void)? = nil
    ) {
        self.fileURL = fileURL
        self.text = text
        self.language = language
        self.preferences = preferences
        self.highlightedRanges = highlightedRanges
        self.ghostSuggestion = ghostSuggestion
        self.completionRequest = completionRequest
        self.jumpRequest = jumpRequest
        self.selectRangeRequest = selectRangeRequest
        self.quickActionRequest = quickActionRequest
        self.findTriggerToken = findTriggerToken
        self.toggleCommentToken = toggleCommentToken
        self.onAcceptPrimaryCompletion = onAcceptPrimaryCompletion
        self.onTextChange = onTextChange
        self.onSelectionChange = onSelectionChange
        self.onToggleAI = onToggleAI
        self.onTriggerGoToLine = onTriggerGoToLine
        self.onTriggerFindBar = onTriggerFindBar
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
        codingBar.languageProvider = { [weak coord] in
            coord?.parent.language ?? .plainText
        }
        codingBar.onAcceptPrimaryCompletion = { [weak coord] in
            coord?.parent.onAcceptPrimaryCompletion() ?? false
        }
        codingBar.onTriggerAI = { [weak coord] in
            coord?.parent.onToggleAI()
        }
        codingBar.onTriggerFind = { [weak coord, weak textView] in
            if let customFind = coord?.parent.onTriggerFindBar {
                customFind()
            } else {
                textView?.findInteraction?.presentFindNavigator(showingReplace: true)
            }
        }
        codingBar.onTriggerGoToLine = { [weak coord] in
            coord?.parent.onTriggerGoToLine()
        }
        codingBar.onAfterProgrammaticEdit = { [weak coord] tv in
            guard let coord else { return }
            coord.isInternalEdit = true
            coord.lastKnownText = tv.text
            coord.parent.onTextChange(tv.text, tv.selectedRange)
            MainActor.assumeIsolated {
                coord.updateGhostOverlay(in: tv)
            }
            DispatchQueue.main.async {
                coord.isInternalEdit = false
            }
        }
        textView.inputAccessoryView = codingBar
        coord.codingBar = codingBar

        let ghostView = GhostCompletionOverlayView()
        ghostView.isHidden = true
        ghostView.onTapAccept = { [weak coord] in
            _ = coord?.parent.onAcceptPrimaryCompletion()
        }
        textView.addSubview(ghostView)
        coord.ghostView = ghostView

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        textView.addGestureRecognizer(pinch)

        applyAppearance(to: textView)
        context.coordinator.loadedAppearanceSignature = "\(preferences.themeSignature)|\(preferences.fontName)|\(Int(preferences.fontSize * 2))"
        context.coordinator.loadState(into: textView, fileURL: fileURL, code: text, language: language, theme: preferences.makeRunestoneTheme())
        return textView
    }

    public func updateUIView(_ textView: TextView, context: Context) {
        context.coordinator.parent = self
        applyAppearance(to: textView)

        let signature = "\(preferences.themeSignature)|\(preferences.fontName)|\(Int(preferences.fontSize * 2))"
        let fileChanged = context.coordinator.loadedFileURL != fileURL
        let languageChanged = context.coordinator.loadedLanguage != language
        let themeChanged = context.coordinator.loadedAppearanceSignature != signature

        // 1. Apply Autocomplete Replacement cleanly via Runestone's Undo-safe replace(_:withText:)
        if let comp = completionRequest, comp.token != context.coordinator.lastCompletionToken {
            context.coordinator.lastCompletionToken = comp.token
            let totalLen = (textView.text as NSString).length
            let safeLoc = min(max(0, comp.range.location), totalLen)
            let safeLen = min(max(0, comp.range.length), totalLen - safeLoc)
            context.coordinator.isInternalEdit = true
            textView.replace(NSRange(location: safeLoc, length: safeLen), withText: comp.replacement)
            if let cursorOffset = comp.cursorOffset {
                let updatedLen = (textView.text as NSString).length
                let targetCursor = min(max(0, safeLoc + cursorOffset), updatedLen)
                textView.selectedRange = NSRange(location: targetCursor, length: 0)
            }
            context.coordinator.ghostView?.isHidden = true
            context.coordinator.lastKnownText = textView.text
            onTextChange(textView.text, textView.selectedRange)
            DispatchQueue.main.async {
                context.coordinator.isInternalEdit = false
            }
            return
        }

        // 2. Toggle Line Comment (Cmd+/ or Command Palette)
        if context.coordinator.lastToggleCommentToken != toggleCommentToken {
            context.coordinator.lastToggleCommentToken = toggleCommentToken
            if ProCodingAccessoryBar.performToggleComment(in: textView, language: language) {
                context.coordinator.isInternalEdit = true
                context.coordinator.ghostView?.isHidden = true
                context.coordinator.lastKnownText = textView.text
                onTextChange(textView.text, textView.selectedRange)
                DispatchQueue.main.async {
                    context.coordinator.isInternalEdit = false
                }
            }
            return
        }

        // 2.5 Quick Action (Undo / Redo / Copy / Paste / Cut / Line / Comment / Move Line / Arrows)
        if let action = quickActionRequest, action.token != context.coordinator.lastQuickActionToken {
            context.coordinator.lastQuickActionToken = action.token
            let mutated = ProCodingAccessoryBar.performAction(action.kind, on: textView, language: language)
            if mutated {
                context.coordinator.isInternalEdit = true
                context.coordinator.ghostView?.isHidden = true
                context.coordinator.lastKnownText = textView.text
                onTextChange(textView.text, textView.selectedRange)
                DispatchQueue.main.async {
                    context.coordinator.isInternalEdit = false
                }
                return
            }
        }

        let externalTextChanged = (!context.coordinator.isInternalEdit && text != context.coordinator.lastKnownText && textView.text != text)

        if fileChanged || languageChanged || themeChanged || externalTextChanged {
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

        // 3. Apply Inline Error / Warning & Find Highlighted Ranges
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

        // 4. Jump to Line (Outline / Problems / Breadcrumb / Go to Line)
        if let jump = jumpRequest, jump.token != context.coordinator.lastJumpToken {
            context.coordinator.lastJumpToken = jump.token
            let zeroBased = max(0, jump.line - 1)
            _ = textView.goToLine(zeroBased, select: .line)
            if !textView.isFirstResponder {
                textView.becomeFirstResponder()
            }
        }

        // 4.5 Select & Scroll to Find Match Range
        if let selReq = selectRangeRequest, selReq.token != context.coordinator.lastSelectRangeToken {
            context.coordinator.lastSelectRangeToken = selReq.token
            let docLen = (textView.text as NSString).length
            let safeLoc = min(max(0, selReq.range.location), docLen)
            let safeLen = min(max(0, selReq.range.length), docLen - safeLoc)
            let safeRange = NSRange(location: safeLoc, length: safeLen)
            textView.selectedRange = safeRange
            textView.scrollRangeToVisible(safeRange)
        }

        // 5. Native Find & Replace Navigator (Fallback)
        if context.coordinator.lastFindToken != findTriggerToken {
            context.coordinator.lastFindToken = findTriggerToken
            textView.findInteraction?.presentFindNavigator(showingReplace: true)
        }

        // 6. VS Code Dimmed Inline Ghost Text Overlay + Tab Button Glow
        context.coordinator.updateGhostOverlay(in: textView)
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
        if language == .go || language == .makefile {
            textView.indentStrategy = .tab(length: preferences.tabWidth)
        } else {
            textView.indentStrategy = .space(length: preferences.tabWidth)
        }
    }

    public final class Coordinator: NSObject, TextViewDelegate {
        var parent: RunestoneEditorView
        weak var ghostView: GhostCompletionOverlayView?
        weak var codingBar: ProCodingAccessoryBar?
        var loadedFileURL: URL?
        var loadedLanguage: CodeLanguage?
        var loadedAppearanceSignature: String = ""
        var lastKnownText: String = ""
        var stateLoadGeneration: Int = 0
        var isInternalEdit: Bool = false
        var lastFindToken: Int = 0
        var lastCompletionToken: Int = 0
        var lastJumpToken: Int = 0
        var lastSelectRangeToken: Int = 0
        var lastToggleCommentToken: Int = 0
        var lastQuickActionToken: Int = 0
        private var pinchStartFontSize: CGFloat = 14.0

        init(parent: RunestoneEditorView) {
            self.parent = parent
            self.lastFindToken = parent.findTriggerToken
            self.lastToggleCommentToken = parent.toggleCommentToken
            self.lastCompletionToken = parent.completionRequest?.token ?? 0
            self.lastJumpToken = parent.jumpRequest?.token ?? 0
            self.lastSelectRangeToken = parent.selectRangeRequest?.token ?? 0
            self.lastQuickActionToken = parent.quickActionRequest?.token ?? 0
        }

        @MainActor
        func updateGhostOverlay(in textView: TextView) {
            guard let ghostView else { return }
            let hasSuggestion = parent.preferences.enableCodeCompletion && parent.ghostSuggestion != nil
            codingBar?.setHasActiveCompletion(hasSuggestion)

            guard parent.preferences.enableCodeCompletion,
                  let candidate = parent.ghostSuggestion,
                  textView.selectedRange.length == 0 else {
                ghostView.isHidden = true
                return
            }

            let cursor = textView.selectedRange.location
            guard let preview = CodeIntelligenceService.ghostPreviewText(
                for: candidate,
                in: textView.text,
                cursor: cursor
            ) else {
                ghostView.isHidden = true
                return
            }

            guard let caretPos = textView.selectedTextRange?.start
                    ?? textView.position(from: textView.beginningOfDocument, offset: cursor) else {
                ghostView.isHidden = true
                return
            }

            let caret = textView.caretRect(for: caretPos)
            guard !caret.isNull, !caret.isInfinite, caret.height > 4 else {
                ghostView.isHidden = true
                return
            }

            let palette = parent.preferences.activePalette
            let baseFont: UIFont
            if parent.preferences.fontName == "System Mono" {
                baseFont = UIFont.monospacedSystemFont(ofSize: parent.preferences.fontSize, weight: .regular)
            } else {
                baseFont = UIFont(name: parent.preferences.fontName, size: parent.preferences.fontSize)
                    ?? UIFont.monospacedSystemFont(ofSize: parent.preferences.fontSize, weight: .regular)
            }
            let ghostFont: UIFont
            if let italicDesc = baseFont.fontDescriptor.withSymbolicTraits(.traitItalic) {
                ghostFont = UIFont(descriptor: italicDesc, size: parent.preferences.fontSize)
            } else {
                ghostFont = baseFont
            }

            ghostView.configure(text: preview, font: ghostFont, palette: palette)

            let originX = caret.maxX + 1
            let visibleMaxX = textView.contentOffset.x + textView.bounds.width - 8
            let availableWidth = visibleMaxX - originX
            guard availableWidth >= 44 else {
                ghostView.isHidden = true
                return
            }

            let size = ghostView.measuredSize(maxWidth: availableWidth, lineHeight: caret.height)
            ghostView.frame = CGRect(x: originX, y: caret.minY, width: size.width, height: size.height)
            ghostView.isHidden = false
            textView.bringSubviewToFront(ghostView)
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
            self.loadedLanguage = language
            self.lastKnownText = code
            self.stateLoadGeneration += 1
            let generation = self.stateLoadGeneration
            let tsLanguage = language.treeSitterLanguage
            DispatchQueue.global(qos: .userInitiated).async {
                let state: TextViewState
                if let tsLanguage {
                    state = TextViewState(text: code, theme: theme, language: tsLanguage)
                } else {
                    state = TextViewState(text: code, theme: theme)
                }
                DispatchQueue.main.async { [weak self, weak textView] in
                    guard let self,
                          let textView,
                          self.stateLoadGeneration == generation,
                          self.loadedFileURL == fileURL,
                          self.loadedLanguage == language else { return }
                    textView.setState(state)
                    if let sel = restoreSelection, sel.location + sel.length <= (code as NSString).length {
                        textView.selectedRange = sel
                    }
                    let docLen = (textView.text as NSString).length
                    textView.highlightedRanges = self.parent.highlightedRanges.filter {
                        $0.range.location >= 0 && $0.range.location + $0.range.length <= docLen && $0.range.length > 0
                    }
                    MainActor.assumeIsolated {
                        self.updateGhostOverlay(in: textView)
                    }
                }
            }
        }

        public func textView(_ textView: TextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            // 1. Hardware Keyboard Tab accepts active VS Code IntelliSense suggestion immediately
            if text == "\t", parent.onAcceptPrimaryCompletion() {
                return false
            }

            // 2. VS Code Smart Auto-Indent on Return (Enter)
            if text == "\n", parent.preferences.autoIndentOnReturn {
                let ns = textView.text as NSString
                let safeLoc = min(max(0, range.location), ns.length)
                let safeEnd = min(max(safeLoc, range.location + range.length), ns.length)

                let lineRange = ns.lineRange(for: NSRange(location: safeLoc, length: 0))
                let lineBeforeCursor = ns.substring(with: NSRange(location: lineRange.location, length: safeLoc - lineRange.location))
                let leadingIndent = String(lineBeforeCursor.prefix(while: { $0 == " " || $0 == "\t" }))

                let indentUnit: String
                if parent.language == .go || parent.language == .makefile {
                    indentUnit = "\t"
                } else if parent.language == .python || parent.language == .nim {
                    indentUnit = "    "
                } else {
                    indentUnit = String(repeating: " ", count: max(parent.preferences.tabWidth, 2))
                }

                let prevChar: String = safeLoc > 0 ? ns.substring(with: NSRange(location: safeLoc - 1, length: 1)) : ""
                let nextChar: String = safeEnd < ns.length ? ns.substring(with: NSRange(location: safeEnd, length: 1)) : ""

                // Case A: Cursor sits right between {|} or (|) or [|] -> expand block with cursor indented inside!
                let isBracketPair = (prevChar == "{" && nextChar == "}")
                    || (prevChar == "(" && nextChar == ")")
                    || (prevChar == "[" && nextChar == "]")

                if isBracketPair {
                    let innerLine = "\n\(leadingIndent)\(indentUnit)"
                    let fullInsert = "\(innerLine)\n\(leadingIndent)"
                    isInternalEdit = true
                    textView.replace(NSRange(location: safeLoc, length: safeEnd - safeLoc), withText: fullInsert)
                    let cursorTarget = safeLoc + (innerLine as NSString).length
                    textView.selectedRange = NSRange(location: min(cursorTarget, (textView.text as NSString).length), length: 0)
                    lastKnownText = textView.text
                    parent.onTextChange(textView.text, textView.selectedRange)
                    DispatchQueue.main.async { [weak self] in self?.isInternalEdit = false }
                    return false
                }

                // Case B: Line before cursor ends with block opener ({, (, [, or : in Python/YAML/C++/Ruby/Lua/Elixir)
                let trimmedBefore = lineBeforeCursor.trimmingCharacters(in: .whitespaces)
                let colonBlockLangs: Set<CodeLanguage> = [.python, .nim, .yaml, .c, .cpp, .objectiveC, .swift, .javascript, .typescript]
                let opensIndent = trimmedBefore.hasSuffix("{")
                    || trimmedBefore.hasSuffix("(")
                    || trimmedBefore.hasSuffix("[")
                    || (trimmedBefore.hasSuffix(":") && colonBlockLangs.contains(parent.language))
                    || ((parent.language == .ruby || parent.language == .elixir || parent.language == .lua) &&
                        (trimmedBefore.hasSuffix(" do") || trimmedBefore.hasSuffix(" then") || trimmedBefore.hasPrefix("def ")))

                if opensIndent {
                    let insert = "\n\(leadingIndent)\(indentUnit)"
                    isInternalEdit = true
                    textView.replace(NSRange(location: safeLoc, length: safeEnd - safeLoc), withText: insert)
                    lastKnownText = textView.text
                    parent.onTextChange(textView.text, textView.selectedRange)
                    DispatchQueue.main.async { [weak self] in self?.isInternalEdit = false }
                    return false
                }

                // Case C: Preserve current line's indentation
                if !leadingIndent.isEmpty {
                    let insert = "\n\(leadingIndent)"
                    isInternalEdit = true
                    textView.replace(NSRange(location: safeLoc, length: safeEnd - safeLoc), withText: insert)
                    lastKnownText = textView.text
                    parent.onTextChange(textView.text, textView.selectedRange)
                    DispatchQueue.main.async { [weak self] in self?.isInternalEdit = false }
                    return false
                }
            }

            return true
        }

        public func textViewDidChange(_ textView: TextView) {
            isInternalEdit = true
            lastKnownText = textView.text
            parent.onTextChange(textView.text, textView.selectedRange)
            MainActor.assumeIsolated {
                self.updateGhostOverlay(in: textView)
            }
            DispatchQueue.main.async { [weak self] in
                self?.isInternalEdit = false
            }
        }

        public func textViewDidChangeSelection(_ textView: TextView) {
            parent.onSelectionChange(textView.selectedRange)
            MainActor.assumeIsolated {
                self.updateGhostOverlay(in: textView)
            }
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

@MainActor
final class GhostCompletionOverlayView: UIControl {
    var onTapAccept: (() -> Void)?

    private let ghostLabel: UILabel = {
        let lbl = UILabel()
        lbl.numberOfLines = 1
        lbl.lineBreakMode = .byTruncatingTail
        lbl.isUserInteractionEnabled = false
        return lbl
    }()

    private let tabBadgeLabel: UILabel = {
        let lbl = UILabel()
        lbl.text = "⇥"
        lbl.textAlignment = .center
        lbl.font = UIFont.monospacedSystemFont(ofSize: 10, weight: .bold)
        lbl.layer.cornerRadius = 3
        lbl.layer.masksToBounds = true
        lbl.isUserInteractionEnabled = false
        return lbl
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 3
        clipsToBounds = true
        addSubview(ghostLabel)
        addSubview(tabBadgeLabel)
        addAction(UIAction { [weak self] _ in
            self?.onTapAccept?()
        }, for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(text: String, font: UIFont, palette: IDEColorPalette) {
        let bg = UIColor(hexString: palette.editorBackground)
        let fg = UIColor(hexString: palette.foreground)
        let accent = UIColor(hexString: palette.accent)

        backgroundColor = bg.withAlphaComponent(0.84)
        ghostLabel.font = font
        ghostLabel.textColor = fg.withAlphaComponent(0.45)
        ghostLabel.text = text

        tabBadgeLabel.textColor = accent
        tabBadgeLabel.backgroundColor = accent.withAlphaComponent(0.18)
    }

    func measuredSize(maxWidth: CGFloat, lineHeight: CGFloat) -> CGSize {
        let badgeWidth: CGFloat = 18
        let gap: CGFloat = 4
        let hPad: CGFloat = 4
        let maxLabelWidth = max(24, maxWidth - badgeWidth - gap - hPad * 2)
        let textSize = ghostLabel.sizeThatFits(CGSize(width: maxLabelWidth, height: lineHeight))
        let w = min(maxWidth, ceil(textSize.width) + badgeWidth + gap + hPad * 2)
        let h = max(ceil(textSize.height), lineHeight)
        return CGSize(width: w, height: h)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let hPad: CGFloat = 3
        let badgeWidth: CGFloat = 18
        let badgeHeight: CGFloat = min(15, max(12, bounds.height - 2))
        let gap: CGFloat = 4
        let labelW = max(0, bounds.width - badgeWidth - gap - hPad * 2)
        ghostLabel.frame = CGRect(x: hPad, y: 0, width: labelW, height: bounds.height)
        tabBadgeLabel.frame = CGRect(
            x: hPad + labelW + gap,
            y: (bounds.height - badgeHeight) / 2,
            width: badgeWidth,
            height: badgeHeight
        )
    }
}
