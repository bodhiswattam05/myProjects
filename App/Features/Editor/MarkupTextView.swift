import CueCore
import SwiftUI
import UIKit

/// Lets the editor's toolbar insert text at the cursor.
@MainActor
final class MarkupTextController {
    fileprivate weak var textView: UITextView?

    func insert(_ snippet: String) {
        guard let textView else { return }
        textView.becomeFirstResponder()
        textView.insertText(snippet)
    }

    /// Wraps the selection in `*…*`, or inserts an empty pair at the cursor.
    func toggleEmphasis() {
        guard let textView, let range = textView.selectedTextRange else { return }
        let selected = textView.text(in: range) ?? ""
        textView.becomeFirstResponder()
        if selected.isEmpty {
            textView.insertText("**")
            if let position = textView.position(from: range.start, offset: 1) {
                textView.selectedTextRange = textView.textRange(from: position, to: position)
            }
        } else {
            textView.replace(range, withText: "*\(selected)*")
            textView.delegate?.textViewDidChange?(textView)
        }
    }

    func dismissKeyboard() {
        textView?.resignFirstResponder()
    }

    /// The selected text and its range, or the whole script when nothing is selected.
    func selectionOrAll() -> (range: NSRange, text: String)? {
        guard let textView else { return nil }
        let text = textView.text ?? ""
        let selected = textView.selectedRange
        if selected.length > 0, let swiftRange = Range(selected, in: text) {
            return (selected, String(text[swiftRange]))
        }
        return (NSRange(location: 0, length: (text as NSString).length), text)
    }

    /// Replaces a range as if typed, so it can be undone with shake or ⌘Z.
    func replace(_ range: NSRange, with replacement: String) {
        guard let textView,
              let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
              let end = textView.position(from: start, offset: range.length),
              let textRange = textView.textRange(from: start, to: end) else { return }
        textView.replace(textRange, withText: replacement)
        // Programmatic edits don't always reach the delegate; make sure the binding updates.
        textView.delegate?.textViewDidChange?(textView)
    }
}

/// A plain-text editor that colours Cue's markup as you type. UIKit because SwiftUI's
/// editor can't restyle ranges without disturbing the cursor.
struct MarkupTextView: UIViewRepresentable {
    @Binding var text: String
    var controller: MarkupTextController
    var placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.adjustsFontForContentSizeCategory = true
        textView.font = Self.baseFont
        textView.textColor = .label
        textView.autocapitalizationType = .sentences
        textView.smartDashesType = .no
        textView.smartQuotesType = .default
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 32, right: 12)
        textView.accessibilityIdentifier = "editor.body"
        textView.accessibilityLabel = String(localized: "Script")
        textView.text = text
        context.coordinator.placeholder.text = placeholder
        context.coordinator.attachPlaceholder(to: textView)
        Self.highlight(textView)
        controller.textView = textView
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        controller.textView = textView
        if textView.text != text {
            textView.text = text
            Self.highlight(textView)
        }
        context.coordinator.updatePlaceholder(for: textView)
    }

    static var baseFont: UIFont {
        UIFont.preferredFont(forTextStyle: .body)
    }

    /// Re-applies colours for the whole text. Scripts are short, so this is cheap, and
    /// only attributes change, so the cursor and undo stack are untouched.
    static func highlight(_ textView: UITextView) {
        let storage = textView.textStorage
        let full = NSRange(location: 0, length: storage.length)
        let base = baseFont
        let accent = UIColor(CueColor.accent)
        let secondary = UIColor(CueColor.secondaryText)

        storage.beginEditing()
        storage.setAttributes([.font: base, .foregroundColor: UIColor.label], range: full)
        for span in MarkupScanner.spans(in: textView.text) {
            let range = NSRange(location: span.location, length: span.length)
            guard NSMaxRange(range) <= storage.length else { continue }
            switch span.kind {
            case .cue:
                storage.addAttributes([
                    .foregroundColor: accent,
                    .font: UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 17, weight: .semibold))
                ], range: range)
            case .emphasis:
                storage.addAttributes([
                    .foregroundColor: accent,
                    .font: base.withTraits(.traitBold)
                ], range: range)
            case .note:
                storage.addAttributes([
                    .foregroundColor: secondary,
                    .font: base.withTraits(.traitItalic)
                ], range: range)
            case .sectionBreak:
                storage.addAttributes([.foregroundColor: secondary, .kern: 4], range: range)
            }
        }
        storage.endEditing()
        textView.typingAttributes = [.font: base, .foregroundColor: UIColor.label]
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        let placeholder = UILabel()

        init(text: Binding<String>) {
            self.text = text
        }

        func attachPlaceholder(to textView: UITextView) {
            placeholder.font = MarkupTextView.baseFont
            placeholder.adjustsFontForContentSizeCategory = true
            placeholder.textColor = UIColor(CueColor.secondaryText)
            placeholder.numberOfLines = 0
            placeholder.translatesAutoresizingMaskIntoConstraints = false
            placeholder.isAccessibilityElement = false
            textView.addSubview(placeholder)
            NSLayoutConstraint.activate([
                placeholder.topAnchor.constraint(equalTo: textView.topAnchor, constant: 12),
                placeholder.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 17),
                placeholder.widthAnchor.constraint(equalTo: textView.widthAnchor, constant: -34)
            ])
            updatePlaceholder(for: textView)
        }

        func updatePlaceholder(for textView: UITextView) {
            placeholder.isHidden = !textView.text.isEmpty
        }

        func textViewDidChange(_ textView: UITextView) {
            MarkupTextView.highlight(textView)
            updatePlaceholder(for: textView)
            text.wrappedValue = textView.text
        }
    }
}

private extension UIFont {
    func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(fontDescriptor.symbolicTraits.union(traits)) else { return self }
        return UIFont(descriptor: descriptor, size: 0)
    }
}
