/// A parsed script: what the prompter shows and what the speaker is expected to say.
///
/// Structure: sections (split by `---`) → lines (one per non-empty source line) → runs.
/// Every spoken word also appears, in order, in `words`, so alignment and timing can
/// work on a flat list while rendering keeps the line layout.
public struct ScriptDocument: Sendable, Equatable {
    public var sections: [ScriptSection]
    /// Every word the speaker is expected to say, in reading order.
    public var words: [ScriptWord]

    public init(sections: [ScriptSection], words: [ScriptWord]) {
        self.sections = sections
        self.words = words
    }

    public static let empty = ScriptDocument(sections: [], words: [])

    public var pauseCount: Int { cueCount(.pause) }
    public var breatheCount: Int { cueCount(.breathe) }
    public var sectionBreakCount: Int { max(0, sections.count - 1) }

    /// The section that contains a given word, or nil if out of range.
    public func sectionIndex(forWord wordIndex: Int) -> Int? {
        guard words.indices.contains(wordIndex) else { return nil }
        return words[wordIndex].sectionIndex
    }

    /// Index of the first word in the section after the one containing `wordIndex`.
    public func firstWordOfNextSection(after wordIndex: Int) -> Int? {
        let current = sectionIndex(forWord: wordIndex) ?? -1
        return words.firstIndex { $0.sectionIndex > current }
    }

    private func cueCount(_ cue: ScriptCue) -> Int {
        sections.reduce(0) { total, section in
            total + section.lines.reduce(0) { lineTotal, line in
                lineTotal + line.runs.filter { $0 == .cue(cue) }.count
            }
        }
    }
}

public struct ScriptSection: Sendable, Equatable, Identifiable {
    public var id: Int
    public var lines: [ScriptLine]

    public init(id: Int, lines: [ScriptLine]) {
        self.id = id
        self.lines = lines
    }

    /// Range of indices into `ScriptDocument.words` covered by this section, if it has words.
    public var wordRange: ClosedRange<Int>? {
        let indices = lines.flatMap { $0.runs.compactMap(\.wordIndex) }
        guard let first = indices.first, let last = indices.last else { return nil }
        return first...last
    }
}

public struct ScriptLine: Sendable, Equatable, Identifiable {
    /// Unique across the whole document.
    public var id: Int
    public var runs: [ScriptRun]

    public init(id: Int, runs: [ScriptRun]) {
        self.id = id
        self.runs = runs
    }

    /// True when the line only holds a note and should render dimmed.
    public var isNoteOnly: Bool {
        !runs.isEmpty && runs.allSatisfy { if case .note = $0 { true } else { false } }
    }
}

public enum ScriptCue: String, Sendable, Equatable, CaseIterable {
    case pause
    case breathe
}

public enum ScriptRun: Sendable, Equatable {
    /// A spoken word. `index` points into `ScriptDocument.words`.
    case word(index: Int, text: String, emphasized: Bool)
    /// A delivery cue such as `[pause]`.
    case cue(ScriptCue)
    /// A `// note to self`. Shown dimmed, never expected to be spoken.
    case note(String)
    /// Text that is shown but has nothing to say aloud, such as a lone dash.
    case literal(String)

    public var wordIndex: Int? {
        if case let .word(index, _, _) = self { index } else { nil }
    }
}

public struct ScriptWord: Sendable, Equatable {
    /// The word as written, including punctuation (for display).
    public var display: String
    /// Lower-cased, punctuation-free form used for matching.
    public var normalized: String
    public var emphasized: Bool
    public var sectionIndex: Int
    public var lineID: Int

    public init(display: String, normalized: String, emphasized: Bool, sectionIndex: Int, lineID: Int) {
        self.display = display
        self.normalized = normalized
        self.emphasized = emphasized
        self.sectionIndex = sectionIndex
        self.lineID = lineID
    }
}
