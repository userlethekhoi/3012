import SwiftUI
import UIKit
import Runestone

public struct RunestoneEditorView: UIViewRepresentable {
    public let fileURL: URL
    public let text: String
    public let language: CodeLanguage
    @ObservedObject public var preferences: EditorPreferences
    public var findTriggerToken: Int
    public var onTextChange: (String, NSRange) -> Void
    public var onSelectionChange: (NSRange) -> Void
    public var onToggleAI: () -> Void

    public init(
        fileURL: URL,
        text: String,
        language: CodeLanguage,
        preferences: EditorPreferences,
        findTriggerToken: Int,
        onTextChange: @escaping (String, NSRange) -> Void,
        onSelectionChange: @escaping (NSRange) -> Void,
        onToggleAI: @escaping () -> Void
    ) {
        self.fileURL = fileURL
        self.text = text
        self.language = language
        self.preferences = preferences
        self.findTriggerToken = findTriggerToken
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
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 6, bottom: 24, right: 10)

        let coord = context.coordinator
        let prefs = preferences
        let codingBar = ProCodingAccessoryBar()
        codingBar.targetTextView = textView
        codingBar.tabWidthProvider = { [weak prefs] in prefs?.tabWidth ?? 2 }
        codingBar.commentPrefixProvider = { [weak coord] in
            coord?.parent.language.lineCommentPrefix ?? "// "
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

        let signature = "\(preferences.selectedThemeID)|\(preferences.fontName)|\(Int(preferences.fontSize * 2))"
        let fileChanged = context.coordinator.loadedFileURL != fileURL
        let themeChanged = context.coordinator.loadedAppearanceSignature != signature
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
        textView.indentStrategy = .space(length: preferences.tabWidth)
    }

    public final class Coordinator: NSObject, TextViewDelegate {
        var parent: RunestoneEditorView
        var loadedFileURL: URL?
        var loadedAppearanceSignature: String = ""
        var isInternalEdit: Bool = false
        var lastFindToken: Int = 0
        private var pinchStartFontSize: CGFloat = 14.0

        init(parent: RunestoneEditorView) {
            self.parent = parent
            self.lastFindToken = parent.findTriggerToken
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
