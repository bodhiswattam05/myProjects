import Testing
@testable import CueCore

@Suite("Markup parser")
struct ScriptParserTests {
    @Test func plainTextBecomesOneSectionWithWords() {
        let document = ScriptParser.parse("Hello there, world.")
        #expect(document.sections.count == 1)
        #expect(document.words.map(\.normalized) == ["hello", "there", "world"])
        #expect(document.words.map(\.display) == ["Hello", "there,", "world."])
    }

    @Test func cuesAreRecognisedCaseInsensitively() {
        let document = ScriptParser.parse("Wait [pause] then [Breathe] go [ pause ]")
        let runs = document.sections[0].lines[0].runs
        #expect(runs.filter { $0 == .cue(.pause) }.count == 2)
        #expect(runs.filter { $0 == .cue(.breathe) }.count == 1)
        #expect(document.words.map(\.normalized) == ["wait", "then", "go"])
        #expect(document.pauseCount == 2)
        #expect(document.breatheCount == 1)
    }

    @Test func unknownBracketsStayAsText() {
        let document = ScriptParser.parse("See [figure] here")
        #expect(document.words.map(\.normalized) == ["see", "figure", "here"])
    }

    @Test func emphasisCanSpanWords() {
        let document = ScriptParser.parse("This is *really very* important")
        #expect(document.words.map(\.emphasized) == [false, false, true, true, false])
        #expect(document.words[2].display == "really")
    }

    @Test func unmatchedAsteriskIsDropped() {
        let document = ScriptParser.parse("Five * stars")
        #expect(document.words.map(\.normalized) == ["five", "stars"])
        #expect(document.words.allSatisfy { !$0.emphasized })
    }

    @Test func notesAreNotSpoken() {
        let document = ScriptParser.parse("Say this // smile here\n// whole line note")
        #expect(document.words.map(\.normalized) == ["say", "this"])
        let lines = document.sections[0].lines
        #expect(lines[0].runs.last == .note("smile here"))
        #expect(lines[1].isNoteOnly)
    }

    @Test func urlsAreNotNotes() {
        let document = ScriptParser.parse("Visit https://example.com today")
        #expect(document.words.count == 3)
        #expect(document.words[1].normalized == "httpsexamplecom")
    }

    @Test func sectionBreaksSplitSections() {
        let document = ScriptParser.parse("One\n---\nTwo three\n\n-----\nFour")
        #expect(document.sections.count == 3)
        #expect(document.words.map(\.sectionIndex) == [0, 1, 1, 2])
        #expect(document.sectionBreakCount == 2)
        #expect(document.sections[1].wordRange == 1...2)
        #expect(document.firstWordOfNextSection(after: 0) == 1)
        #expect(document.firstWordOfNextSection(after: 3) == nil)
    }

    @Test func leadingAndDoubleBreaksDoNotCreateEmptySections() {
        let document = ScriptParser.parse("---\n---\nOnly\n---\n")
        #expect(document.sections.count == 1)
    }

    @Test func punctuationOnlyTokensAreShownButNotSpoken() {
        let document = ScriptParser.parse("Yes — no & maybe")
        #expect(document.words.map(\.normalized) == ["yes", "no", "and", "maybe"])
        #expect(document.sections[0].lines[0].runs.contains(.literal("—")))
    }

    @Test func emptyInput() {
        let document = ScriptParser.parse("  \n\n ")
        #expect(document == .empty)
    }

    @Test func wordIndicesMatchRuns() {
        let document = ScriptParser.parse("A *b* [pause] c // n\n---\nd e")
        let indices = document.sections.flatMap { $0.lines.flatMap { $0.runs.compactMap(\.wordIndex) } }
        #expect(indices == Array(document.words.indices))
    }
}

@Suite("Markup scanner")
struct MarkupScannerTests {
    @Test func findsEverySpanKind() {
        let text = "Hi *there* [pause]\n---\nOk // note"
        let spans = MarkupScanner.spans(in: text)
        #expect(spans.map(\.kind) == [.emphasis, .cue, .sectionBreak, .note])
        let ns = Array(text.utf16)
        func string(_ span: MarkupScanner.Span) -> String {
            String(decoding: ns[span.location..<(span.location + span.length)], as: UTF16.self)
        }
        #expect(spans.map(string) == ["*there*", "[pause]", "---", "// note"])
    }

    @Test func usesUTF16Offsets() {
        let text = "😀 [pause]"
        let spans = MarkupScanner.spans(in: text)
        #expect(spans.first?.location == 3)
        #expect(spans.first?.length == 7)
    }
}
