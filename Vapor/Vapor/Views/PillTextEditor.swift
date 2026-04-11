import SwiftUI
import AppKit

/// A custom text editor for the pill view that:
/// - Intercepts ⌘K, ⇧⌘C, ⌘↩, ⌘Y, ⌘/ before NSTextView processes them
/// - Auto-scrolls to bottom during dictation
/// - Two-way text binding
/// - Transparent background to match pill material
struct PillTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var isDictating: Bool
    var placeholder: String = "Hold Fn to dictate or type here…"

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = InterceptingTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = .labelColor
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.autoresizingMask = [.width]

        // Word wrap
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        textView.delegate = context.coordinator
        textView.onFocusChange = { focused in
            DispatchQueue.main.async {
                context.coordinator.parent.isFocused = focused
            }
        }
        context.coordinator.textView = textView

        scrollView.documentView = textView

        // Set initial text
        textView.string = text
        context.coordinator.updatePlaceholder()

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? InterceptingTextView else { return }

        // Update text if it changed externally (e.g., from dictation)
        if textView.string != text {
            let wasAtEnd = isScrolledToBottom(scrollView)

            // Use shouldChangeText/didChangeText to register with the undo manager.
            // Use NSAttributedString with explicit font + color so text doesn't
            // revert to black when the text storage applies default attributes.
            let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: textView.font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor.labelColor
            ]
            let attributed = NSAttributedString(string: text, attributes: attrs)
            context.coordinator.isUpdating = true
            if textView.shouldChangeText(in: fullRange, replacementString: text) {
                textView.textStorage?.replaceCharacters(in: fullRange, with: attributed)
                textView.didChangeText()
            }
            context.coordinator.isUpdating = false
            context.coordinator.updatePlaceholder()

            // Auto-scroll to bottom during dictation or if user was already at bottom
            if isDictating || wasAtEnd {
                textView.scrollRangeToVisible(NSRange(location: textView.string.count, length: 0))
            }
        }
    }

    private func isScrolledToBottom(_ scrollView: NSScrollView) -> Bool {
        let clipView = scrollView.contentView
        let documentHeight = scrollView.documentView?.frame.height ?? 0
        let clipHeight = clipView.bounds.height
        let scrollY = clipView.bounds.origin.y
        return scrollY + clipHeight >= documentHeight - 10
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PillTextEditor
        weak var textView: InterceptingTextView?
        var isUpdating = false

        init(_ parent: PillTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let textView = notification.object as? NSTextView else { return }
            isUpdating = true
            parent.text = textView.string
            updatePlaceholder()
            isUpdating = false
        }

        func updatePlaceholder() {
            guard let textView else { return }
            if textView.string.isEmpty {
                textView.placeholderString = parent.placeholder
            } else {
                textView.placeholderString = nil
            }
        }
    }
}

// MARK: - InterceptingTextView

/// NSTextView subclass that intercepts keyboard shortcuts before the standard responder chain.
class InterceptingTextView: NSTextView {
    /// Placeholder text shown when the text view is empty.
    var placeholderString: String? {
        didSet { needsDisplay = true }
    }

    /// Callback for focus state changes.
    var onFocusChange: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { updateFocusState() }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { onFocusChange?(false) }
        return result
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Remove old observers before re-adding to prevent duplicates
        NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        guard let window else { return }
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowKeyChanged),
            name: NSWindow.didBecomeKeyNotification, object: window
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowKeyChanged),
            name: NSWindow.didResignKeyNotification, object: window
        )
        // Auto-focus when first added to window so glow appears immediately
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func windowKeyChanged() {
        updateFocusState()
    }

    private func updateFocusState() {
        let focused = (window?.isKeyWindow == true) && (window?.firstResponder == self)
        onFocusChange?(focused)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }

        let chars = event.charactersIgnoringModifiers ?? ""

        // Check for shift+command combos before single-modifier checks
        if event.modifierFlags.contains(.shift) {
            switch chars {
            case "z":
                // ⌘⇧Z — Redo: pass through to NSTextView's undo manager
                return super.performKeyEquivalent(with: event)
            case "c":
                // ⌘⇧C — Copy Original (full text)
                NotificationCenter.default.post(name: .vaporCopyOriginal, object: nil)
                return true
            default:
                break
            }
        }

        switch chars {
        case "a":
            // ⌘A — Select All
            selectAll(nil)
            return true

        case "z":
            // ⌘Z — Undo: pass through to NSTextView's undo manager
            return super.performKeyEquivalent(with: event)

        case "k":
            // ⌘K — Copy & Clear
            NotificationCenter.default.post(name: .vaporCopyAndClear, object: nil)
            return true

        case "c":
            // ⌘C — standard copy: pass through to NSTextView
            // (⌘⇧C is handled in the shift check above)
            return super.performKeyEquivalent(with: event)

        case "\r":
            // ⌘↩ — Compress & Copy
            NotificationCenter.default.post(name: .vaporCompressAndCopy, object: nil)
            return true

        case "y":
            // ⌘Y — Show History
            NotificationCenter.default.post(name: .vaporShowHistory, object: nil)
            return true

        case "/":
            // ⌘/ — Show Help
            NotificationCenter.default.post(name: .vaporShowHelp, object: nil)
            return true

        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Draw placeholder when empty
        if string.isEmpty, let placeholder = placeholderString {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font ?? .monospacedSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor.placeholderTextColor
            ]
            let inset = textContainerInset
            let rect = NSRect(
                x: inset.width + 5,
                y: inset.height,
                width: bounds.width - inset.width * 2 - 10,
                height: bounds.height - inset.height * 2
            )
            (placeholder as NSString).draw(in: rect, withAttributes: attrs)
        }
    }
}
