import UIKit
import Runestone

public final class ProCodingAccessoryBar: UIInputView {
    public weak var targetTextView: TextView?
    public var tabWidthProvider: (() -> Int)?
    public var commentPrefixProvider: (() -> String)?
    public var onTriggerAI: (() -> Void)?
    public var onTriggerFind: (() -> Void)?

    private var isSelectionMode: Bool = false {
        didSet {
            selectButton?.backgroundColor = isSelectionMode ? UIColor.systemBlue : UIColor.white.withAlphaComponent(0.12)
        }
    }
    private weak var selectButton: UIButton?
    private var accumulatedX: CGFloat = 0
    private var accumulatedY: CGFloat = 0
    private let feedback = UIImpactFeedbackGenerator(style: .light)

    public init() {
        super.init(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 46), inputViewStyle: .keyboard)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        backgroundColor = UIColor(red: 0.10, green: 0.11, blue: 0.15, alpha: 0.98)
        autoresizingMask = [.flexibleWidth]

        let topBorder = UIView()
        topBorder.translatesAutoresizingMaskIntoConstraints = false
        topBorder.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        addSubview(topBorder)

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        addSubview(scrollView)

        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .center
        scrollView.addSubview(stack)

        // Fixed right button: dismiss keyboard
        let hideKBButton = makeActionButton(title: "▾", systemIcon: "keyboard.chevron.compact.down", accent: false) { [weak self] in
            self?.targetTextView?.resignFirstResponder()
        }
        hideKBButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hideKBButton)

        NSLayoutConstraint.activate([
            topBorder.topAnchor.constraint(equalTo: topAnchor),
            topBorder.leadingAnchor.constraint(equalTo: leadingAnchor),
            topBorder.trailingAnchor.constraint(equalTo: trailingAnchor),
            topBorder.heightAnchor.constraint(equalToConstant: 0.5),

            hideKBButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -6),
            hideKBButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            hideKBButton.widthAnchor.constraint(equalToConstant: 36),
            hideKBButton.heightAnchor.constraint(equalToConstant: 34),

            scrollView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 6),
            scrollView.trailingAnchor.constraint(equalTo: hideKBButton.leadingAnchor, constant: -6),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])

        // 1. AI Quick Button
        let aiBtn = makeActionButton(title: "✨ AI", systemIcon: nil, accent: true) { [weak self] in
            self?.feedback.impactOccurred()
            self?.onTriggerAI?()
        }
        stack.addArrangedSubview(aiBtn)

        // 2. Trackpad Pill (Drag to move cursor / select code)
        let trackpadView = makeTrackpadPill()
        stack.addArrangedSubview(trackpadView)

        // 3. Select Toggle
        let selBtn = makeActionButton(title: "Sel", systemIcon: nil, accent: false) { [weak self] in
            guard let self else { return }
            self.feedback.impactOccurred()
            self.isSelectionMode.toggle()
        }
        self.selectButton = selBtn
        stack.addArrangedSubview(selBtn)

        // 4. Tab Key
        let tabBtn = makeActionButton(title: "⇥", systemIcon: nil, accent: false) { [weak self] in
            guard let self, let tv = self.targetTextView else { return }
            self.feedback.impactOccurred()
            let spaces = String(repeating: " ", count: self.tabWidthProvider?() ?? 2)
            tv.insertText(spaces)
        }
        stack.addArrangedSubview(tabBtn)

        // 5. Flick Keys (Tap = primary, Swipe Up = secondary!)
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
            stack.addArrangedSubview(key)
        }

        // 6. Undo / Redo / Find
        let undoBtn = makeActionButton(title: nil, systemIcon: "arrow.uturn.backward", accent: false) { [weak self] in
            self?.feedback.impactOccurred()
            self?.targetTextView?.undoManager?.undo()
        }
        let redoBtn = makeActionButton(title: nil, systemIcon: "arrow.uturn.forward", accent: false) { [weak self] in
            self?.feedback.impactOccurred()
            self?.targetTextView?.undoManager?.redo()
        }
        let findBtn = makeActionButton(title: nil, systemIcon: "magnifyingglass", accent: false) { [weak self] in
            self?.feedback.impactOccurred()
            self?.onTriggerFind?()
        }
        stack.addArrangedSubview(undoBtn)
        stack.addArrangedSubview(redoBtn)
        stack.addArrangedSubview(findBtn)
    }

    private func makeTrackpadPill() -> UIView {
        let pill = UIView()
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.backgroundColor = UIColor.systemIndigo.withAlphaComponent(0.32)
        pill.layer.cornerRadius = 8
        pill.layer.borderWidth = 1
        pill.layer.borderColor = UIColor.systemIndigo.withAlphaComponent(0.7).cgColor

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "✥ Trackpad"
        label.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .white
        pill.addSubview(label)

        NSLayoutConstraint.activate([
            pill.widthAnchor.constraint(equalToConstant: 86),
            pill.heightAnchor.constraint(equalToConstant: 34),
            label.centerXAnchor.constraint(equalTo: pill.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: pill.centerYAnchor)
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
                moveCursorHorizontally(in: tv, offset: delta)
                feedback.impactOccurred()
            }

            while abs(accumulatedY) >= stepY {
                let goingDown = accumulatedY > 0
                accumulatedY -= (goingDown ? 1 : -1) * stepY
                moveCursorVertically(in: tv, down: goingDown)
                feedback.impactOccurred()
            }
        default:
            break
        }
    }

    private func moveCursorHorizontally(in tv: TextView, offset: Int) {
        let totalLen = (tv.text as NSString).length
        let current = tv.selectedRange
        if isSelectionMode {
            let newEnd = min(max(0, current.location + current.length + offset), totalLen)
            if newEnd >= current.location {
                tv.selectedRange = NSRange(location: current.location, length: newEnd - current.location)
            } else {
                tv.selectedRange = NSRange(location: newEnd, length: current.location - newEnd)
            }
        } else {
            let base = offset > 0 ? (current.location + current.length) : current.location
            let nextLoc = min(max(0, base + offset), totalLen)
            tv.selectedRange = NSRange(location: nextLoc, length: 0)
        }
        tv.scrollRangeToVisible(tv.selectedRange)
    }

    private func moveCursorVertically(in tv: TextView, down: Bool) {
        let nsText = tv.text as NSString
        let totalLen = nsText.length
        guard totalLen > 0 else { return }
        let pos = min(tv.selectedRange.location, totalLen)
        let currentLineRange = nsText.lineRange(for: NSRange(location: pos, length: 0))
        let colOffset = pos - currentLineRange.location

        let targetLocation: Int
        if down {
            let nextLineStart = currentLineRange.location + currentLineRange.length
            guard nextLineStart < totalLen else {
                targetLocation = totalLen
                applyVerticalMove(in: tv, to: targetLocation)
                return
            }
            let nextLineRange = nsText.lineRange(for: NSRange(location: nextLineStart, length: 0))
            let usableLen = max(0, nextLineRange.length - 1)
            targetLocation = nextLineRange.location + min(colOffset, usableLen)
        } else {
            guard currentLineRange.location > 0 else {
                applyVerticalMove(in: tv, to: 0)
                return
            }
            let prevLineRange = nsText.lineRange(for: NSRange(location: currentLineRange.location - 1, length: 0))
            let usableLen = max(0, prevLineRange.length - 1)
            targetLocation = prevLineRange.location + min(colOffset, usableLen)
        }
        applyVerticalMove(in: tv, to: min(max(0, targetLocation), totalLen))
    }

    private func applyVerticalMove(in tv: TextView, to location: Int) {
        if isSelectionMode {
            let anchor = tv.selectedRange.location
            let start = min(anchor, location)
            let length = abs(location - anchor)
            tv.selectedRange = NSRange(location: start, length: length)
        } else {
            tv.selectedRange = NSRange(location: location, length: 0)
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
            btn.setImage(UIImage(systemName: systemIcon, withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)), for: .normal)
        } else if let title {
            btn.setTitle(title, for: .normal)
            btn.titleLabel?.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .semibold)
            btn.setTitleColor(.white, for: .normal)
        }
        let width: CGFloat = (title?.count ?? 1) > 2 ? 54 : 36
        NSLayoutConstraint.activate([
            btn.widthAnchor.constraint(equalToConstant: width),
            btn.heightAnchor.constraint(equalToConstant: 34)
        ])
        btn.addAction(UIAction { _ in action() }, for: .touchUpInside)
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
        mainLbl.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .bold)
        mainLbl.textColor = .white
        mainLbl.isUserInteractionEnabled = false

        container.addSubview(topHint)
        container.addSubview(mainLbl)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 34),
            container.heightAnchor.constraint(equalToConstant: 34),
            topHint.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
            topHint.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            mainLbl.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -3),
            mainLbl.centerXAnchor.constraint(equalTo: container.centerXAnchor)
        ])

        container.addAction(UIAction { [weak self] _ in
            guard let self, let tv = self.targetTextView else { return }
            self.feedback.impactOccurred()
            if autoPairPrimary && secondary.count == 1 {
                tv.insertText(primary + secondary)
                let cur = tv.selectedRange
                if cur.location > 0 {
                    tv.selectedRange = NSRange(location: cur.location - 1, length: 0)
                }
            } else {
                tv.insertText(primary)
            }
        }, for: .touchUpInside)

        let swipeUp = UISwipeGestureRecognizer(target: nil, action: nil)
        swipeUp.direction = .up
        container.addGestureRecognizer(VerticalFlickGesture { [weak self] in
            guard let self, let tv = self.targetTextView else { return }
            self.feedback.impactOccurred()
            if secondary == "//" {
                let prefix = self.commentPrefixProvider?() ?? "// "
                tv.insertText(prefix)
            } else {
                tv.insertText(secondary)
            }
        })

        return container
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
