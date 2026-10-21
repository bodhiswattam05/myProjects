import Foundation

/// Finds markup in raw editor text so the editor can style it while the user types.
/// Uses the same rules as `ScriptParser`.
public enum MarkupScanner {
    public enum Kind: Sendable, Equatable {
        case cue
        case emphasis
        case note
        case sectionBreak
    }

    public struct Span: Sendable, Equatable {
        public var kind: Kind
        /// Offsets in UTF-16 code units, which is what `NSRange` and TextKit use.
        public var location: Int
        public var length: Int
    }

    public static func spans(in text: String) -> [Span] {
        var spans: [Span] = []
        let utf16 = text.utf16
        func offset(_ index: String.Index) -> Int { utf16.distance(from: utf16.startIndex, to: index) }
        func add(_ kind: Kind, _ range: Range<String.Index>) {
            spans.append(Span(kind: kind, location: offset(range.lowerBound), length: utf16.distance(from: range.lowerBound, to: range.upperBound)))
        }

        var lineStart = text.startIndex
        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(where: \.isNewline) ?? text.endIndex
            let line = text[lineStart..<lineEnd]
            if ScriptParser.isSectionBreak(line.trimmingCharacters(in: .whitespaces)) {
                add(.sectionBreak, line.startIndex..<line.endIndex)
            } else {
                var body = line
                if let note = ScriptParser.noteStart(in: line) {
                    add(.note, note..<line.endIndex)
                    body = line[..<note]
                }
                var index = body.startIndex
                var emphasisStart: String.Index?
                while index < body.endIndex {
                    if body[index] == "[", let (_, after) = ScriptParser.cue(in: body, at: index) {
                        add(.cue, index..<after)
                        index = after
                        continue
                    }
                    if body[index] == "*" {
                        let after = body.index(after: index)
                        if let start = emphasisStart {
                            add(.emphasis, start..<after)
                            emphasisStart = nil
                        } else if body[after...].contains("*") {
                            emphasisStart = index
                        }
                    }
                    index = body.index(after: index)
                }
            }
            lineStart = lineEnd < text.endIndex ? text.index(after: lineEnd) : text.endIndex
        }
        return spans
    }
}
