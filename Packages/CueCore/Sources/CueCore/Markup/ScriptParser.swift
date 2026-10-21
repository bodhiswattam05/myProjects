import Foundation

/// Parses Cue's lightweight markup:
///
/// - `[pause]`, `[breathe]`: delivery cues (case-insensitive)
/// - `*emphasis*`: may span several words within one line
/// - `// note to self`: runs to the end of the line, shown dimmed, never spoken.
///   It must start the line or follow whitespace, so `https://` stays text.
/// - `---` on its own line: section break
public enum ScriptParser {
    public static func parse(_ source: String) -> ScriptDocument {
        var builder = Builder()
        for rawLine in source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if isSectionBreak(line) {
                builder.breakSection()
                continue
            }
            builder.parseLine(Substring(line))
        }
        return builder.finish()
    }

    static func isSectionBreak(_ line: some StringProtocol) -> Bool {
        line.count >= 3 && line.allSatisfy { $0 == "-" }
    }

    /// Index where a `//` note begins in the line, if any.
    static func noteStart(in line: Substring) -> Substring.Index? {
        var index = line.startIndex
        while index < line.endIndex {
            let next = line.index(after: index)
            if line[index] == "/", next < line.endIndex, line[next] == "/" {
                if index == line.startIndex || line[line.index(before: index)].isWhitespace {
                    return index
                }
            }
            index = next
        }
        return nil
    }

    /// Matches `[pause]` / `[breathe]` starting at `index`. Returns the cue and the index after `]`.
    static func cue(in line: Substring, at index: Substring.Index) -> (ScriptCue, Substring.Index)? {
        guard line[index] == "[", let close = line[index...].firstIndex(of: "]") else { return nil }
        let name = line[line.index(after: index)..<close].trimmingCharacters(in: .whitespaces).lowercased()
        guard let cue = ScriptCue(rawValue: name) else { return nil }
        return (cue, line.index(after: close))
    }

    private struct Builder {
        var sections: [ScriptSection] = []
        var currentLines: [ScriptLine] = []
        var words: [ScriptWord] = []
        var nextLineID = 0

        mutating func breakSection() {
            // Consecutive or leading breaks don't create empty sections.
            guard !currentLines.isEmpty else { return }
            sections.append(ScriptSection(id: sections.count, lines: currentLines))
            currentLines = []
        }

        mutating func finish() -> ScriptDocument {
            breakSection()
            return ScriptDocument(sections: sections, words: words)
        }

        mutating func parseLine(_ line: Substring) {
            let lineID = nextLineID
            nextLineID += 1
            var runs: [ScriptRun] = []
            var body = line
            var note: String?
            if let start = ScriptParser.noteStart(in: line) {
                body = line[..<start]
                note = line[line.index(start, offsetBy: 2)...].trimmingCharacters(in: .whitespaces)
            }

            var buffer = ""
            var bufferEmphasized = false
            var emphasized = false

            func flush() {
                guard !buffer.isEmpty else { return }
                let normalized = Normalizer.normalize(buffer)
                if normalized.isEmpty {
                    runs.append(.literal(buffer))
                } else {
                    let index = words.count
                    words.append(ScriptWord(
                        display: buffer,
                        normalized: normalized,
                        emphasized: bufferEmphasized,
                        sectionIndex: sections.count,
                        lineID: lineID
                    ))
                    runs.append(.word(index: index, text: buffer, emphasized: bufferEmphasized))
                }
                buffer = ""
            }

            var index = body.startIndex
            while index < body.endIndex {
                let character = body[index]
                if character == "[", let (cue, after) = ScriptParser.cue(in: body, at: index) {
                    flush()
                    runs.append(.cue(cue))
                    index = after
                    continue
                }
                if character == "*" {
                    let rest = body[body.index(after: index)...]
                    if emphasized {
                        flush()
                        emphasized = false
                    } else if rest.contains("*") {
                        flush()
                        emphasized = true
                    }
                    // An unmatched `*` is dropped rather than shown.
                    index = body.index(after: index)
                    continue
                }
                if character.isWhitespace {
                    flush()
                } else {
                    if buffer.isEmpty { bufferEmphasized = emphasized }
                    buffer.append(character)
                }
                index = body.index(after: index)
            }
            flush()

            if let note, !note.isEmpty {
                runs.append(.note(note))
            }
            guard !runs.isEmpty else { return }
            currentLines.append(ScriptLine(id: lineID, runs: runs))
        }
    }
}
