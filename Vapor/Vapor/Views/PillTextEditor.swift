import SwiftUI
import AppKit

/// A custom text editor for the pill view that:
/// - Intercepts ⌘K, ⌘C (no selection), ⌘↩, ⌘Y, ⌘/ before NSTextView processes them
/// - Auto-scrolls to bottom during dictation
/// - Two-way text binding
/// - Transparent background to match pill material
struct PillTextEditor: NSViewRepresentable {
    @Binding var text: String
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
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.autoresizingMask = [.width]

        // Word wrap
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        textView.delegate = context.coordinator
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
            textView.string = text
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
        private var isUpdating = false

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

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }

        let chars = event.charactersIgnoringModifiers ?? ""

        switch chars {
        case "k":
            // ⌘K — Copy & Clear
            NotificationCenter.default.post(name: .vaporCopyAndClear, object: nil)
            return true

        case "c":
            // ⌘C — if text is selected, use normal copy; otherwise copy full original
            if let selectedRange = selectedRanges.first as? NSValue {
                let range = selectedRange.rangeValue
                if range.length > 0 {
                    // There's a selection — let normal copy handle it
                    return super.performKeyEquivalent(with: event)
                }
            }
            // No selection — copy full original
            NotificationCenter.default.post(name: .vaporCopyOriginal, object: nil)
            return true

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
                .font: font ?? .systemFont(ofSize: 13),
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
