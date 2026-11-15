import UIKit
import Runestone

public final class ProCodingAccessoryBar: UIInputView {
    public weak var targetTextView: TextView?
    public var tabWidthProvider: (() -> Int)?
    public var commentPrefixProvider: (() -> String)?
    public var languageProvider: (() -> CodeLanguage)?
    public var onAcceptPrimaryCompletion: (() -> Bool)?
    public var onTriggerAI: (() -> Void)?
    public var onTriggerFind: (() -> Void)?
    public var onTriggerGoToLine: (() -> Void)?
    public var onAfterProgrammaticEdit: ((TextView) -> Void)?

    private var hasActiveCompletion: Bool = false
    private weak var tabButton: UIButton?
    private var selectionAnchor: Int? = nil
    private var isSelectionMode: Bool = false {
        didSet {
            selectButton?.backgroundColor = isSelectionMode ? UIColor.systemBlue : UIColor.white.withAlphaComponent(0.12)
            if isSelectionMode {
                if let tv = targetTextView {
                    let maxLen = (tv.text as NSString).length
                    selectionAnchor = clampRange(tv.selectedRange, maxLength: maxLen).location
                }
            } else {
                selectionAnchor = nil
            }
        }
    }
    private weak var selectButton: UIButton?
    private weak var compactToggleButton: UIButton?
    private weak var rowDividerView: UIView?
    private weak var row2ScrollView: UIScrollView?
    private var isCompactBar: Bool = UserDefaults.standard.bool(forKey: "3012.compactCodingBar")
    private var accumulatedX: CGFloat = 0
    private var accumulatedY: CGFloat = 0
    private let feedback = UIImpactFeedbackGenerator(style: .light)

    public override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: isCompactBar ? 36 : 64)
    }

    public func setHasActiveCompletion(_ active: Bool) {
        hasActiveCompletion = active
        tabButton?.backgroundColor = active
            ? UIColor.systemBlue.withAlphaComponent(0.92)
            : UIColor.white.withAlphaComponent(0.12)
    }

    public init() {
        let compact = UserDefaults.standard.bool(forKey: "3012.compactCodingBar")
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: compact ? 36 : 64), inputViewStyle: .keyboard)
        self.allowsSelfSizing = true
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.allowsSelfSizing = true
        setupUI()
    }

    private func setupUI() {
        backgroundColor = UIColor(red: 0.10, green: 0.11, blue: 0.15, alpha: 0.98)
        autoresizingMask = [.flexibleWidth]

        let topBorder = UIView()
        topBorder.translatesAutoresizingMaskIntoConstraints = false
        topBorder.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        addSubview(topBorder)

        let rowDivider = UIView()
        rowDivider.translatesAutoresizingMaskIntoConstraints = false
        rowDivider.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        addSubview(rowDivider)
        self.rowDividerView = rowDivider

        // Row 1: Undo / Redo / Copy / Paste / Cut / Select / Arrows / Home / End / Trackpad + Slim/Expand & Hide Keyboard
        let row1Scroll = UIScrollView()
        row1Scroll.translatesAutoresizingMaskIntoConstraints = false
        row1Scroll.showsHorizontalScrollIndicator = false
        row1Scroll.alwaysBounceHorizontal = true
        addSubview(row1Scroll)

        let row1Stack = UIStackView()
        row1Stack.translatesAutoresizingMaskIntoConstraints = false
        row1Stack.axis = .horizontal
        row1Stack.spacing = 5
        row1Stack.alignment = .center
        row1Scroll.addSubview(row1Stack)

        let compactBtn = makeActionButton(
            title: nil,
            systemIcon: isCompactBar ? "chevron.up" : "chevron.down",
            accent: false
        ) { [weak self] in
            guard let self else { return }
            self.feedback.impactOccurred()
            self.isCompactBar.toggle()
            UserDefaults.standard.set(self.isCompactBar, forKey: "3012.compactCodingBar")
            self.applyCompactState(reloadKeyboard: true)
        }
        compactBtn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(compactBtn)
        self.compactToggleButton = compactBtn

        let hideKBButton = makeActionButton(title: nil, systemIcon: "keyboard.chevron.compact.down", accent: false) { [weak self] in
            self?.targetTextView?.resignFirstResponder()
        }
        hideKBButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hideKBButton)

        // Row 2: AI / Tab / Flick Symbols / Duplicate Line / Delete Line / Find
        let row2Scroll = UIScrollView()
        row2Scroll.translatesAutoresizingMaskIntoConstraints = false
        row2Scroll.showsHorizontalScrollIndicator = false
        row2Scroll.alwaysBounceHorizontal = true
        addSubview(row2Scroll)
        self.row2ScrollView = row2Scroll

        let row2Stack = UIStackView()
        row2Stack.translatesAutoresizingMaskIntoConstraints = false
        row2Stack.axis = .horizontal
        row2Stack.spacing = 5
        row2Stack.alignment = .center
        row2Scroll.addSubview(row2Stack)

        NSLayoutConstraint.activate([
            topBorder.topAnchor.constraint(equalTo: topAnchor),
            topBorder.leadingAnchor.constraint(equalTo: leadingAnchor),
            topBorder.trailingAnchor.constraint(equalTo: trailingAnchor),
            topBorder.heightAnchor.constraint(equalToConstant: 0.5),

            hideKBButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -6),
            hideKBButton.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            hideKBButton.widthAnchor.constraint(equalToConstant: 34),
            hideKBButton.heightAnchor.constraint(equalToConstant: 29),

            compactBtn.trailingAnchor.constraint(equalTo: hideKBButton.leadingAnchor, constant: -4),
            compactBtn.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            compactBtn.widthAnchor.constraint(equalToConstant: 28),
            compactBtn.heightAnchor.constraint(equalToConstant: 29),

            row1Scroll.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 6),
            row1Scroll.trailingAnchor.constraint(equalTo: compactBtn.leadingAnchor, constant: -5),
            row1Scroll.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            row1Scroll.heightAnchor.constraint(equalToConstant: 32),

            row1Stack.leadingAnchor.constraint(equalTo: row1Scroll.contentLayoutGuide.leadingAnchor),
            row1Stack.trailingAnchor.constraint(equalTo: row1Scroll.contentLayoutGuide.trailingAnchor),
            row1Stack.topAnchor.constraint(equalTo: row1Scroll.contentLayoutGuide.topAnchor),
            row1Stack.bottomAnchor.constraint(equalTo: row1Scroll.contentLayoutGuide.bottomAnchor),
            row1Stack.heightAnchor.constraint(equalTo: row1Scroll.frameLayoutGuide.heightAnchor),

            rowDivider.leadingAnchor.constraint(equalTo: leadingAnchor),
            rowDivider.trailingAnchor.constraint(equalTo: trailingAnchor),
            rowDivider.topAnchor.constraint(equalTo: row1Scroll.bottomAnchor),
            rowDivider.heightAnchor.constraint(equalToConstant: 0.5),

            row2Scroll.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 6),
            row2Scroll.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -6),
            row2Scroll.topAnchor.constraint(equalTo: rowDivider.bottomAnchor),
            row2Scroll.heightAnchor.constraint(equalToConstant: 30.5),

            row2Stack.leadingAnchor.constraint(equalTo: row2Scroll.contentLayoutGuide.leadingAnchor),
            row2Stack.trailingAnchor.constraint(equalTo: row2Scroll.contentLayoutGuide.trailingAnchor),
            row2Stack.topAnchor.constraint(equalTo: row2Scroll.contentLayoutGuide.topAnchor),
            row2Stack.bottomAnchor.constraint(equalTo: row2Scroll.contentLayoutGuide.bottomAnchor),
            row2Stack.heightAnchor.constraint(equalTo: row2Scroll.frameLayoutGuide.heightAnchor)
        ])

        applyCompactState(reloadKeyboard: false)

        // MARK: Populate Row 1 — Quick Undo/Redo, Copy/Paste/Cut, Arrows & Trackpad
        let undoBtn = makeActionButton(title: nil, systemIcon: "arrow.uturn.backward", accent: false) { [weak self] in
            self?.triggerQuick(.undo)
        }
        let redoBtn = makeActionButton(title: nil, systemIcon: "arrow.uturn.forward", accent: false) { [weak self] in
            self?.triggerQuick(.redo)
        }
        let copyBtn = makeActionButton(title: nil, systemIcon: "doc.on.doc", accent: false) { [weak self] in
            self?.triggerQuick(.copy)
        }
        let pasteBtn = makeActionButton(title: nil, systemIcon: "doc.on.clipboard", accent: false) { [weak self] in
            self?.triggerQuick(.paste)
        }
        let cutBtn = makeActionButton(title: nil, systemIcon: "scissors", accent: false) { [weak self] in
            self?.triggerQuick(.cut)
        }
        let selBtn = makeActionButton(title: nil, systemIcon: "selection.pin.in.out", accent: false) { [weak self] in
            guard let self else { return }
            self.feedback.impactOccurred()
            self.isSelectionMode.toggle()
        }
        self.selectButton = selBtn

        let leftArrow = makeRepeatableArrowButton(systemIcon: "arrow.left") { [weak self] in
            self?.triggerQuick(.moveLeft, haptic: false)
        }
        let downArrow = makeRepeatableArrowButton(systemIcon: "arrow.down") { [weak self] in
            self?.triggerQuick(.moveDown, haptic: false)
        }
        let upArrow = makeRepeatableArrowButton(systemIcon: "arrow.up") { [weak self] in
            self?.triggerQuick(.moveUp, haptic: false)
        }
        let rightArrow = makeRepeatableArrowButton(systemIcon: "arrow.right") { [weak self] in
            self?.triggerQuick(.moveRight, haptic: false)
        }
        let homeBtn = makeActionButton(title: nil, systemIcon: "arrow.left.to.line", accent: false) { [weak self] in
            self?.triggerQuick(.moveLineStart)
        }
        let endBtn = makeActionButton(title: nil, systemIcon: "arrow.right.to.line", accent: false) { [weak self] in
            self?.triggerQuick(.moveLineEnd)
        }
        let selectAllBtn = makeActionButton(title: "All", systemIcon: nil, accent: false) { [weak self] in
            self?.triggerQuick(.selectAll)
        }
        let trackpadView = makeTrackpadPill()

        for v in [undoBtn, redoBtn, makeGroupSpacer(), copyBtn, pasteBtn, cutBtn, makeGroupSpacer(), selBtn, leftArrow, downArrow, upArrow, rightArrow, homeBtn, endBtn, selectAllBtn, makeGroupSpacer(), trackpadView] {
            row1Stack.addArrangedSubview(v)
        }

        // MARK: Populate Row 2 — AI, Tab, Flick Symbols, Line Ops, Find
        let aiBtn = makeActionButton(title: nil, systemIcon: "cpu", accent: true) { [weak self] in
            self?.feedback.impactOccurred()
            self?.onTriggerAI?()
        }
        row2Stack.addArrangedSubview(aiBtn)

        let tabBtn = makeActionButton(title: nil, systemIcon: "arrow.right.to.line", accent: false) { [weak self] in
            guard let self, let tv = self.targetTextView else { return }
            self.feedback.impactOccurred()
            if self.onAcceptPrimaryCompletion?() == true {
                return
            }
            let lang = self.languageProvider?() ?? .plainText
            let indentText: String
            if lang == .go || lang == .makefile {
                indentText = "\t"
            } else {
                indentText = String(repeating: " ", count: max(1, self.tabWidthProvider?() ?? 2))
            }
            tv.insertText(indentText)
            self.onAfterProgrammaticEdit?(tv)
        }
        self.tabButton = tabBtn
        if hasActiveCompletion {
            tabBtn.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.92)
        }
        row2Stack.addArrangedSubview(tabBtn)

        let flickConfigs: [(String, String, Bool)] = [
            ("{", "}", true),
            ("(", ")", true),
            ("[", "]", true),
            ("<", ">", false),
            ("\"", "'", true),
            ("=", "=>", false),
            (";", ":", false),
            ("/", "//", false),
            ("$", "`", false),
            ("&", "|", false),
            ("!", "?", false),
            ("_", "-", false)
        ]

        for (primary, secondary, autoPair) in flickConfigs {
            let key = makeFlickKeyButton(primary: primary, secondary: secondary, autoPairPrimary: autoPair)
            row2Stack.addArrangedSubview(key)
        }

        let commentBtn = makeActionButton(title: "//", systemIcon: nil, accent: false) { [weak self] in
            self?.triggerQuick(.toggleComment)
        }
        let moveUpBtn = makeActionButton(title: nil, systemIcon: "arrow.up.square", accent: false) { [weak self] in
            self?.triggerQuick(.moveLineUp)
        }
        let moveDownBtn = makeActionButton(title: nil, systemIcon: "arrow.down.square", accent: false) { [weak self] in
            self?.triggerQuick(.moveLineDown)
        }
        let dupLineBtn = makeActionButton(title: nil, systemIcon: "plus.square.on.square", accent: false) { [weak self] in
            self?.triggerQuick(.duplicateLine)
        }
        let delLineBtn = makeActionButton(title: nil, systemIcon: "delete.left", accent: false) { [weak self] in
            self?.triggerQuick(.deleteLine)
        }
        let goToLineBtn = makeActionButton(title: ":Ln", systemIcon: nil, accent: false) { [weak self] in
            self?.feedback.impactOccurred()
            self?.onTriggerGoToLine?()
        }
        let findBtn = makeActionButton(title: nil, systemIcon: "magnifyingglass", accent: false) { [weak self] in
            self?.feedback.impactOccurred()
            self?.onTriggerFind?()
        }
        for v in [makeGroupSpacer(), commentBtn, moveUpBtn, moveDownBtn, dupLineBtn, delLineBtn, goToLineBtn, findBtn] {
            row2Stack.addArrangedSubview(v)
        }
    }

    private func makeGroupSpacer() -> UIView {
        let sep = UIView()
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        NSLayoutConstraint.activate([
            sep.widthAnchor.constraint(equalToConstant: 1),
            sep.heightAnchor.constraint(equalToConstant: 18)
        ])
        return sep
    }

    private func triggerQuick(_ kind: EditorQuickActionKind, haptic: Bool = true) {
        guard let tv = targetTextView else { return }
        if haptic {
            feedback.impactOccurred()
        }
        let lang = languageProvider?() ?? .plainText
        var anchorCopy = selectionAnchor
        let mutated = Self.performAction(
            kind,
            on: tv,
            isSelectionMode: isSelectionMode,
            selectionAnchor: &anchorCopy,
            language: lang
        )
        selectionAnchor = isSelectionMode ? anchorCopy : nil
        if mutated {
            onAfterProgrammaticEdit?(tv)
        }
    }

    // MARK: - Shared Action Execution (Used by both Accessory Bar and SwiftUI Header/Toolbar)
    @MainActor
    @discardableResult
    public static func performAction(
        _ kind: EditorQuickActionKind,
        on tv: TextView,
        isSelectionMode: Bool = false,
        language: CodeLanguage = .plainText
    ) -> Bool {
        var ignoredAnchor: Int? = nil
        return performAction(
            kind,
            on: tv,
            isSelectionMode: isSelectionMode,
            selectionAnchor: &ignoredAnchor,
            language: language
        )
    }

    @MainActor
    @discardableResult
    private static func performAction(
        _ kind: EditorQuickActionKind,
        on tv: TextView,
        isSelectionMode: Bool,
        selectionAnchor: inout Int?,
        language: CodeLanguage
    ) -> Bool {
        switch kind {
        case .undo:
            tv.undoManager?.undo()
            return true
        case .redo:
            tv.undoManager?.redo()
            return true
        case .copy:
            performCopy(in: tv)
            return false
        case .paste:
            return performPaste(in: tv)
        case .cut:
            return performCut(in: tv)
        case .selectAll:
            let len = (tv.text as NSString).length
            selectionAnchor = isSelectionMode ? 0 : nil
            tv.selectedRange = NSRange(location: 0, length: len)
            return false
        case .duplicateLine:
            return performDuplicateLine(in: tv)
        case .deleteLine:
            return performDeleteLine(in: tv)
        case .toggleComment:
            return performToggleComment(in: tv, language: language)
        case .moveLineUp:
            return performMoveLine(in: tv, down: false)
        case .moveLineDown:
            return performMoveLine(in: tv, down: true)
        case .moveLeft:
            moveCursorHorizontally(in: tv, offset: -1, isSelectionMode: isSelectionMode, selectionAnchor: &selectionAnchor)
            return false
        case .moveRight:
            moveCursorHorizontally(in: tv, offset: 1, isSelectionMode: isSelectionMode, selectionAnchor: &selectionAnchor)
            return false
        case .moveUp:
            moveCursorVertically(in: tv, down: false, isSelectionMode: isSelectionMode, selectionAnchor: &selectionAnchor)
            return false
        case .moveDown:
            moveCursorVertically(in: tv, down: true, isSelectionMode: isSelectionMode, selectionAnchor: &selectionAnchor)
            return false
        case .moveLineStart:
            moveCursorToLineEdge(in: tv, toEnd: false, isSelectionMode: isSelectionMode, selectionAnchor: &selectionAnchor)
            return false
        case .moveLineEnd:
            moveCursorToLineEdge(in: tv, toEnd: true, isSelectionMode: isSelectionMode, selectionAnchor: &selectionAnchor)
            return false
        }
    }

    @MainActor
    private static func performCopy(in tv: TextView) {
        let ns = tv.text as NSString
        guard ns.length > 0 else { return }
        let safeSel = clampRange(tv.selectedRange, maxLength: ns.length)
        if safeSel.length > 0 {
            UIPasteboard.general.string = ns.substring(with: safeSel)
        } else {
            let lineRange = ns.lineRange(for: NSRange(location: safeSel.location, length: 0))
            UIPasteboard.general.string = ns.substring(with: lineRange)
        }
    }

    @MainActor
    private static func performPaste(in tv: TextView) -> Bool {
        guard let clip = UIPasteboard.general.string, !clip.isEmpty else { return false }
        let ns = tv.text as NSString
        let safeSel = clampRange(tv.selectedRange, maxLength: ns.length)
        tv.replace(safeSel, withText: clip)
        let cursor = min(safeSel.location + (clip as NSString).length, (tv.text as NSString).length)
        tv.selectedRange = NSRange(location: cursor, length: 0)
        tv.scrollRangeToVisible(tv.selectedRange)
        return true
    }

    @MainActor
    private static func performCut(in tv: TextView) -> Bool {
        let ns = tv.text as NSString
        guard ns.length > 0 else { return false }
        let safeSel = clampRange(tv.selectedRange, maxLength: ns.length)
        let targetRange: NSRange = safeSel.length > 0
            ? safeSel
            : ns.lineRange(for: NSRange(location: safeSel.location, length: 0))
        UIPasteboard.general.string = ns.substring(with: targetRange)
        tv.replace(targetRange, withText: "")
        let newLen = (tv.text as NSString).length
        tv.selectedRange = NSRange(location: min(targetRange.location, newLen), length: 0)
        tv.scrollRangeToVisible(tv.selectedRange)
        return true
    }

    @MainActor
    private static func performDuplicateLine(in tv: TextView) -> Bool {
        let ns = tv.text as NSString
        let safeSel = clampRange(tv.selectedRange, maxLength: ns.length)
        let lineRange = ns.lineRange(for: safeSel)
        let lineText = ns.substring(with: lineRange)
        let insertionText = lineText.hasSuffix("\n") ? lineText : "\n" + lineText
        let insertLoc = lineRange.location + lineRange.length
        tv.replace(NSRange(location: insertLoc, length: 0), withText: insertionText)
        let targetCursor = min(insertLoc + (lineText.hasSuffix("\n") ? (safeSel.location - lineRange.location) : 1 + (safeSel.location - lineRange.location)), (tv.text as NSString).length)
        tv.selectedRange = NSRange(location: max(0, targetCursor), length: 0)
        tv.scrollRangeToVisible(tv.selectedRange)
        return true
    }

    @MainActor
    private static func performDeleteLine(in tv: TextView) -> Bool {
        let ns = tv.text as NSString
        guard ns.length > 0 else { return false }
        let safeSel = clampRange(tv.selectedRange, maxLength: ns.length)
        var lineRange = ns.lineRange(for: safeSel)
        // If deleting the final line without trailing newline and a previous newline exists, include it
        if lineRange.location > 0 && lineRange.location + lineRange.length == ns.length && !ns.substring(with: lineRange).hasSuffix("\n") {
            lineRange = NSRange(location: lineRange.location - 1, length: lineRange.length + 1)
        }
        tv.replace(lineRange, withText: "")
        let newLen = (tv.text as NSString).length
        tv.selectedRange = NSRange(location: min(lineRange.location, newLen), length: 0)
        tv.scrollRangeToVisible(tv.selectedRange)
        return true
    }

    @MainActor
    public static func performToggleComment(in tv: TextView, language: CodeLanguage) -> Bool {
        let ns = tv.text as NSString
        let safeSel = clampRange(tv.selectedRange, maxLength: ns.length)

        // Block comment markers for HTML/XML/Vue/Svelte/Markdown/CSS
        if [.html, .xml, .vue, .svelte, .markdown, .css].contains(language) {
            let openToken = (language == .css) ? "/* " : "<!-- "
            let closeToken = (language == .css) ? " */" : " -->"
            let openTrim = openToken.trimmingCharacters(in: .whitespaces)
            let closeTrim = closeToken.trimmingCharacters(in: .whitespaces)

            if ns.length == 0 {
                tv.insertText(openToken + closeToken)
                tv.selectedRange = NSRange(location: (openToken as NSString).length, length: 0)
                return true
            }

            let targetRange: NSRange
            if safeSel.length > 0 {
                targetRange = safeSel
            } else {
                let rawLine = ns.lineRange(for: safeSel)
                let rawStr = ns.substring(with: rawLine)
                let noNewline = rawStr.hasSuffix("\n") ? String(rawStr.dropLast()) : rawStr
                let leadCount = (String(noNewline.prefix { $0 == " " || $0 == "\t" }) as NSString).length
                let innerLen = max(0, (noNewline as NSString).length - leadCount)
                targetRange = NSRange(location: rawLine.location + leadCount, length: innerLen)
            }

            let snippet = ns.substring(with: targetRange)
            let trimmedSnippet = snippet.trimmingCharacters(in: .whitespaces)
            if trimmedSnippet.isEmpty {
                let inserted = openToken + closeToken
                tv.replace(targetRange, withText: inserted)
                tv.selectedRange = NSRange(location: targetRange.location + (openToken as NSString).length, length: 0)
                return true
            }

            if trimmedSnippet.hasPrefix(openTrim) && trimmedSnippet.hasSuffix(closeTrim) {
                var unwrapped = trimmedSnippet
                if unwrapped.hasPrefix(openToken) {
                    unwrapped.removeFirst(openToken.count)
                } else {
                    unwrapped.removeFirst(openTrim.count)
                }
                if unwrapped.hasSuffix(closeToken) {
                    unwrapped.removeLast(closeToken.count)
                } else if unwrapped.hasSuffix(closeTrim) {
                    unwrapped.removeLast(closeTrim.count)
                }
                tv.replace(targetRange, withText: unwrapped)
                return true
            } else {
                let wrapped = openToken + snippet + closeToken
                tv.replace(targetRange, withText: wrapped)
                return true
            }
        }

        // Standard line comment prefix (// , # , -- , % , ; )
        let prefix = language.lineCommentPrefix
        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespaces)
        guard ns.length > 0 else {
            tv.insertText(prefix)
            return true
        }

        var effectiveSel = safeSel
        if safeSel.length > 0,
           ns.substring(with: NSRange(location: safeSel.location + safeSel.length - 1, length: 1)) == "\n" {
            effectiveSel.length -= 1
        }
        let lineRange = ns.lineRange(for: effectiveSel)
        let block = ns.substring(with: lineRange)
        let hasTrailingNewline = block.hasSuffix("\n")
        var lines = block.components(separatedBy: "\n")
        if hasTrailingNewline && lines.last == "" {
            lines.removeLast()
        }

        let nonEmptyLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let allCommented = !nonEmptyLines.isEmpty && nonEmptyLines.allSatisfy {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix(trimmedPrefix)
        }

        let transformed = lines.map { line -> String in
            let indent = String(line.prefix { $0 == " " || $0 == "\t" })
            let body = String(line.dropFirst(indent.count))
            if allCommented {
                if body.hasPrefix(prefix) {
                    return indent + String(body.dropFirst(prefix.count))
                } else if body.hasPrefix(trimmedPrefix) {
                    return indent + String(body.dropFirst(trimmedPrefix.count))
                }
                return line
            } else {
                if line.trimmingCharacters(in: .whitespaces).isEmpty && lines.count > 1 {
                    return line
                }
                return indent + prefix + body
            }
        }
        let replacement = transformed.joined(separator: "\n") + (hasTrailingNewline ? "\n" : "")
        tv.replace(lineRange, withText: replacement)
        return true
    }

    @MainActor
    public static func performMoveLine(in tv: TextView, down: Bool) -> Bool {
        let ns = tv.text as NSString
        guard ns.length > 0 else { return false }
        let safeSel = clampRange(tv.selectedRange, maxLength: ns.length)

        var effectiveSel = safeSel
        if safeSel.length > 0,
           ns.substring(with: NSRange(location: safeSel.location + safeSel.length - 1, length: 1)) == "\n" {
            effectiveSel.length -= 1
        }
        let blockRange = ns.lineRange(for: effectiveSel)
        let cursorOffsetInBlock = safeSel.location - blockRange.location

        if !down {
            guard blockRange.location > 0 else { return false }
            let prevLineRange = ns.lineRange(for: NSRange(location: blockRange.location - 1, length: 0))
            let blockText = ns.substring(with: blockRange)
            let prevText = ns.substring(with: prevLineRange)

            let swappedFirst: String
            let swappedSecond: String
            if !blockText.hasSuffix("\n") && prevText.hasSuffix("\n") {
                swappedFirst = blockText + "\n"
                swappedSecond = String(prevText.dropLast())
            } else {
                swappedFirst = blockText
                swappedSecond = prevText
            }
            let combinedRange = NSRange(location: prevLineRange.location, length: prevLineRange.length + blockRange.length)
            tv.replace(combinedRange, withText: swappedFirst + swappedSecond)
            let newLen = (tv.text as NSString).length
            let targetLoc = min(max(0, prevLineRange.location + cursorOffsetInBlock), newLen)
            let targetLen = min(safeSel.length, newLen - targetLoc)
            tv.selectedRange = NSRange(location: targetLoc, length: targetLen)
            tv.scrollRangeToVisible(tv.selectedRange)
            return true
        } else {
            let afterBlockLoc = blockRange.location + blockRange.length
            guard afterBlockLoc < ns.length else { return false }
            let nextLineRange = ns.lineRange(for: NSRange(location: afterBlockLoc, length: 0))
            let blockText = ns.substring(with: blockRange)
            let nextText = ns.substring(with: nextLineRange)

            let swappedFirst: String
            let swappedSecond: String
            if !nextText.hasSuffix("\n") && blockText.hasSuffix("\n") {
                swappedFirst = nextText + "\n"
                swappedSecond = String(blockText.dropLast())
            } else {
                swappedFirst = nextText
                swappedSecond = blockText
            }
            let combinedRange = NSRange(location: blockRange.location, length: blockRange.length + nextLineRange.length)
            tv.replace(combinedRange, withText: swappedFirst + swappedSecond)
            let newLen = (tv.text as NSString).length
            let targetLoc = min(max(0, blockRange.location + (swappedFirst as NSString).length + cursorOffsetInBlock), newLen)
            let targetLen = min(safeSel.length, newLen - targetLoc)
            tv.selectedRange = NSRange(location: targetLoc, length: targetLen)
            tv.scrollRangeToVisible(tv.selectedRange)
            return true
        }
    }

    private static func clampRange(_ range: NSRange, maxLength: Int) -> NSRange {
        let loc = min(max(0, range.location), maxLength)
        let len = min(max(0, range.length), maxLength - loc)
        return NSRange(location: loc, length: len)
    }

    // MARK: - Trackpad Pill
    private func makeTrackpadPill() -> UIView {
        let pill = UIView()
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.backgroundColor = UIColor.systemIndigo.withAlphaComponent(0.30)
        pill.layer.cornerRadius = 7
        pill.layer.borderWidth = 1
        pill.layer.borderColor = UIColor.systemIndigo.withAlphaComponent(0.65).cgColor

        let row = UIStackView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.axis = .horizontal
        row.spacing = 4
        row.alignment = .center
        row.isUserInteractionEnabled = false

        let iconView = UIImageView(
            image: UIImage(
                systemName: "dpad",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            )
        )
        iconView.tintColor = .white

        let label = UILabel()
        label.text = "Trackpad"
        label.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .white

        row.addArrangedSubview(iconView)
        row.addArrangedSubview(label)
        pill.addSubview(row)

        NSLayoutConstraint.activate([
            pill.widthAnchor.constraint(equalToConstant: 82),
            pill.heightAnchor.constraint(equalToConstant: 29),
            row.centerXAnchor.constraint(equalTo: pill.centerXAnchor),
            row.centerYAnchor.constraint(equalTo: pill.centerYAnchor)
        ])

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleTrackpadPan(_:)))
        pill.addGestureRecognizer(pan)
        return pill
    }

    @objc private func handleTrackpadPan(_ gesture: UIPanGestureRecognizer) {
        guard let tv = targetTextView else { return }
        switch gesture.state {
        case .began:
            accumulatedX = 0
            accumulatedY = 0
            feedback.prepare()
        case .changed:
            let translation = gesture.translation(in: self)
            gesture.setTranslation(.zero, in: self)
            accumulatedX += translation.x
            accumulatedY += translation.y

            let stepX: CGFloat = 11.0
            let stepY: CGFloat = 18.0

            while abs(accumulatedX) >= stepX {
                let delta = accumulatedX > 0 ? 1 : -1
                accumulatedX -= CGFloat(delta) * stepX
                var anchorCopy = selectionAnchor
                Self.moveCursorHorizontally(in: tv, offset: delta, isSelectionMode: isSelectionMode, selectionAnchor: &anchorCopy)
                selectionAnchor = isSelectionMode ? anchorCopy : nil
                feedback.impactOccurred()
            }

            while abs(accumulatedY) >= stepY {
                let goingDown = accumulatedY > 0
                accumulatedY -= (goingDown ? 1 : -1) * stepY
                var anchorCopy = selectionAnchor
                Self.moveCursorVertically(in: tv, down: goingDown, isSelectionMode: isSelectionMode, selectionAnchor: &anchorCopy)
                selectionAnchor = isSelectionMode ? anchorCopy : nil
                feedback.impactOccurred()
            }
        default:
            break
        }
    }

    private func applyCompactState(reloadKeyboard: Bool) {
        rowDividerView?.isHidden = isCompactBar
        row2ScrollView?.isHidden = isCompactBar
        let iconName = isCompactBar ? "chevron.up" : "chevron.down"
        compactToggleButton?.setImage(
            UIImage(systemName: iconName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 11.5, weight: .semibold)),
            for: .normal
        )
        invalidateIntrinsicContentSize()
        frame.size.height = isCompactBar ? 36 : 64
        setNeedsLayout()
        layoutIfNeeded()
        if reloadKeyboard {
            targetTextView?.reloadInputViews()
        }
    }

    private static func lineUsableLength(in nsText: NSString, lineRange: NSRange) -> Int {
        guard lineRange.length > 0 else { return 0 }
        let lineEnd = lineRange.location + lineRange.length
        if lineRange.length >= 2, lineEnd <= nsText.length {
            let tail2 = nsText.substring(with: NSRange(location: lineEnd - 2, length: 2))
            if tail2 == "\r\n" { return max(0, lineRange.length - 2) }
        }
        if lineEnd <= nsText.length {
            let lastChar = nsText.substring(with: NSRange(location: lineEnd - 1, length: 1))
            if lastChar == "\n" || lastChar == "\r" { return max(0, lineRange.length - 1) }
        }
        return lineRange.length
    }

    private static func alignedComposedLocation(_ loc: Int, in nsText: NSString) -> Int {
        let clamped = min(max(0, loc), nsText.length)
        guard clamped > 0 && clamped < nsText.length else { return clamped }
        let seq = nsText.rangeOfComposedCharacterSequence(at: clamped)
        return seq.location
    }

    private static func resolvedActiveEdge(in range: NSRange, anchor: inout Int?) -> Int {
        let a = anchor ?? range.location
        anchor = a
        if range.length == 0 {
            return range.location
        }
        return range.location < a ? range.location : (range.location + range.length)
    }

    @MainActor
    private static func moveCursorHorizontally(
        in tv: TextView,
        offset: Int,
        isSelectionMode: Bool,
        selectionAnchor: inout Int?
    ) {
        let ns = tv.text as NSString
        let totalLen = ns.length
        let current = clampRange(tv.selectedRange, maxLength: totalLen)

        func stepComposedLocation(from pos: Int, delta: Int) -> Int {
            guard delta != 0 else { return pos }
            if delta > 0 {
                guard pos < totalLen else { return totalLen }
                let seq = ns.rangeOfComposedCharacterSequence(at: pos)
                return min(totalLen, seq.location + max(1, seq.length))
            } else {
                guard pos > 0 else { return 0 }
                let seq = ns.rangeOfComposedCharacterSequence(at: pos - 1)
                return max(0, seq.location)
            }
        }

        if isSelectionMode {
            let curEnd = resolvedActiveEdge(in: current, anchor: &selectionAnchor)
            let anchor = min(max(0, selectionAnchor ?? current.location), totalLen)
            let newEnd = stepComposedLocation(from: curEnd, delta: offset)
            let start = min(anchor, newEnd)
            let length = abs(newEnd - anchor)
            tv.selectedRange = NSRange(location: start, length: length)
        } else {
            selectionAnchor = nil
            let base = offset > 0 ? (current.location + current.length) : current.location
            let nextLoc = stepComposedLocation(from: base, delta: offset)
            tv.selectedRange = NSRange(location: nextLoc, length: 0)
        }
        tv.scrollRangeToVisible(tv.selectedRange)
    }

    @MainActor
    private static func moveCursorVertically(
        in tv: TextView,
        down: Bool,
        isSelectionMode: Bool,
        selectionAnchor: inout Int?
    ) {
        let nsText = tv.text as NSString
        let totalLen = nsText.length
        guard totalLen > 0 else { return }
        let safeSel = clampRange(tv.selectedRange, maxLength: totalLen)
        let pos = isSelectionMode ? resolvedActiveEdge(in: safeSel, anchor: &selectionAnchor) : safeSel.location
        let currentLineRange = nsText.lineRange(for: NSRange(location: pos, length: 0))
        let colOffset = pos - currentLineRange.location

        let targetLocation: Int
        if down {
            let nextLineStart = currentLineRange.location + currentLineRange.length
            guard nextLineStart < totalLen else {
                applyVerticalMove(in: tv, to: totalLen, isSelectionMode: isSelectionMode, selectionAnchor: &selectionAnchor)
                return
            }
            let nextLineRange = nsText.lineRange(for: NSRange(location: nextLineStart, length: 0))
            let usableLen = lineUsableLength(in: nsText, lineRange: nextLineRange)
            targetLocation = nextLineRange.location + min(colOffset, usableLen)
        } else {
            guard currentLineRange.location > 0 else {
                applyVerticalMove(in: tv, to: 0, isSelectionMode: isSelectionMode, selectionAnchor: &selectionAnchor)
                return
            }
            let prevLineRange = nsText.lineRange(for: NSRange(location: currentLineRange.location - 1, length: 0))
            let usableLen = lineUsableLength(in: nsText, lineRange: prevLineRange)
            targetLocation = prevLineRange.location + min(colOffset, usableLen)
        }
        let aligned = alignedComposedLocation(targetLocation, in: nsText)
        applyVerticalMove(in: tv, to: aligned, isSelectionMode: isSelectionMode, selectionAnchor: &selectionAnchor)
    }

    @MainActor
    private static func moveCursorToLineEdge(
        in tv: TextView,
        toEnd: Bool,
        isSelectionMode: Bool,
        selectionAnchor: inout Int?
    ) {
        let nsText = tv.text as NSString
        let totalLen = nsText.length
        guard totalLen > 0 else { return }
        let safeSel = clampRange(tv.selectedRange, maxLength: totalLen)
        let pos = isSelectionMode ? resolvedActiveEdge(in: safeSel, anchor: &selectionAnchor) : safeSel.location
        let lineRange = nsText.lineRange(for: NSRange(location: pos, length: 0))
        let usableLen = lineUsableLength(in: nsText, lineRange: lineRange)
        let targetLoc = toEnd ? (lineRange.location + usableLen) : lineRange.location
        let aligned = alignedComposedLocation(targetLoc, in: nsText)
        applyVerticalMove(in: tv, to: aligned, isSelectionMode: isSelectionMode, selectionAnchor: &selectionAnchor)
    }

    @MainActor
    private static func applyVerticalMove(
        in tv: TextView,
        to location: Int,
        isSelectionMode: Bool,
        selectionAnchor: inout Int?
    ) {
        let totalLen = (tv.text as NSString).length
        let clampedTarget = min(max(0, location), totalLen)
        if isSelectionMode {
            let anchor = min(max(0, selectionAnchor ?? clampRange(tv.selectedRange, maxLength: totalLen).location), totalLen)
            selectionAnchor = anchor
            let start = min(anchor, clampedTarget)
            let length = abs(clampedTarget - anchor)
            tv.selectedRange = NSRange(location: start, length: length)
        } else {
            selectionAnchor = nil
            tv.selectedRange = NSRange(location: clampedTarget, length: 0)
        }
        tv.scrollRangeToVisible(tv.selectedRange)
    }

    private func makeActionButton(title: String?, systemIcon: String?, accent: Bool, action: @escaping () -> Void) -> UIButton {
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.backgroundColor = accent ? UIColor.systemBlue.withAlphaComponent(0.85) : UIColor.white.withAlphaComponent(0.12)
        btn.tintColor = .white
        btn.layer.cornerRadius = 7
        if let systemIcon {
            btn.setImage(UIImage(systemName: systemIcon, withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)), for: .normal)
        } else if let title {
            btn.setTitle(title, for: .normal)
            btn.titleLabel?.font = UIFont.monospacedSystemFont(ofSize: 11.5, weight: .semibold)
            btn.setTitleColor(.white, for: .normal)
        }
        let width: CGFloat = (title?.count ?? 1) > 2 ? 40 : 33
        NSLayoutConstraint.activate([
            btn.widthAnchor.constraint(equalToConstant: width),
            btn.heightAnchor.constraint(equalToConstant: 29)
        ])
        btn.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return btn
    }

    private func makeRepeatableArrowButton(systemIcon: String, action: @escaping () -> Void) -> UIButton {
        let btn = RepeatableActionButton(onStep: action)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        btn.tintColor = .white
        btn.layer.cornerRadius = 7
        btn.setImage(UIImage(systemName: systemIcon, withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)), for: .normal)
        NSLayoutConstraint.activate([
            btn.widthAnchor.constraint(equalToConstant: 32),
            btn.heightAnchor.constraint(equalToConstant: 29)
        ])
        return btn
    }

    private func makeFlickKeyButton(primary: String, secondary: String, autoPairPrimary: Bool) -> UIView {
        let container = UIButton(type: .system)
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        container.layer.cornerRadius = 7

        let topHint = UILabel()
        topHint.translatesAutoresizingMaskIntoConstraints = false
        topHint.text = secondary
        topHint.font = UIFont.monospacedSystemFont(ofSize: 8.5, weight: .medium)
        topHint.textColor = UIColor.white.withAlphaComponent(0.48)
        topHint.isUserInteractionEnabled = false

        let mainLbl = UILabel()
        mainLbl.translatesAutoresizingMaskIntoConstraints = false
        mainLbl.text = primary
        mainLbl.font = UIFont.monospacedSystemFont(ofSize: 13.5, weight: .bold)
        mainLbl.textColor = .white
        mainLbl.isUserInteractionEnabled = false

        container.addSubview(topHint)
        container.addSubview(mainLbl)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 33),
            container.heightAnchor.constraint(equalToConstant: 29),
            topHint.topAnchor.constraint(equalTo: container.topAnchor, constant: 1),
            topHint.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            mainLbl.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2),
            mainLbl.centerXAnchor.constraint(equalTo: container.centerXAnchor)
        ])

        container.addAction(UIAction { [weak self] _ in
            guard let self, let tv = self.targetTextView else { return }
            self.feedback.impactOccurred()
            if autoPairPrimary, let closing = Self.closingPair(for: primary) {
                let ns = tv.text as NSString
                let sel = tv.selectedRange
                if sel.length > 0 && sel.location >= 0 && sel.location + sel.length <= ns.length {
                    let selectedText = ns.substring(with: sel)
                    let wrapped = primary + selectedText + closing
                    tv.replace(sel, withText: wrapped)
                    let innerLoc = sel.location + (primary as NSString).length
                    tv.selectedRange = NSRange(location: innerLoc, length: (selectedText as NSString).length)
                } else {
                    tv.insertText(primary + closing)
                    let cur = tv.selectedRange
                    let closeLen = (closing as NSString).length
                    if cur.location >= closeLen {
                        tv.selectedRange = NSRange(location: cur.location - closeLen, length: 0)
                    }
                }
            } else {
                tv.insertText(primary)
            }
            self.onAfterProgrammaticEdit?(tv)
        }, for: .touchUpInside)

        container.addGestureRecognizer(VerticalFlickGesture { [weak self] in
            guard let self, let tv = self.targetTextView else { return }
            self.feedback.impactOccurred()
            if secondary == "//" {
                let prefix = self.commentPrefixProvider?() ?? "// "
                tv.insertText(prefix)
            } else {
                tv.insertText(secondary)
            }
            self.onAfterProgrammaticEdit?(tv)
        })

        return container
    }

    private static func closingPair(for opener: String) -> String? {
        switch opener {
        case "{": return "}"
        case "(": return ")"
        case "[": return "]"
        case "\"": return "\""
        case "'": return "'"
        default: return nil
        }
    }
}

private final class RepeatableActionButton: UIButton {
    private let onStep: () -> Void
    private var repeatTask: Task<Void, Never>?

    init(onStep: @escaping () -> Void) {
        self.onStep = onStep
        super.init(frame: .zero)
        addTarget(self, action: #selector(touchBegan), for: .touchDown)
        addTarget(self, action: #selector(touchEnded), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil {
            stopRepeating()
        }
    }

    @objc private func touchBegan() {
        stopRepeating()
        onStep()
        repeatTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 280_000_000)
            while !Task.isCancelled {
                guard let self, self.isHighlighted || self.isTracking else { break }
                self.onStep()
                try? await Task.sleep(nanoseconds: 65_000_000)
            }
        }
    }

    @objc private func touchEnded() {
        stopRepeating()
    }

    private func stopRepeating() {
        repeatTask?.cancel()
        repeatTask = nil
    }
}

private final class VerticalFlickGesture: UIPanGestureRecognizer {
    private let onFlickUp: () -> Void
    private var didFire = false

    init(onFlickUp: @escaping () -> Void) {
        self.onFlickUp = onFlickUp
        super.init(target: nil, action: nil)
        addTarget(self, action: #selector(handlePan))
    }

    @objc private func handlePan() {
        switch state {
        case .began:
            didFire = false
        case .changed:
            let t = translation(in: view)
            if !didFire && t.y < -14 && abs(t.y) > abs(t.x) {
                didFire = true
                onFlickUp()
            }
        default:
            break
        }
    }
}
