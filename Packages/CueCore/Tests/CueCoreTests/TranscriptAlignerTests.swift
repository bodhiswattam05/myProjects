import Testing
@testable import CueCore

@Suite("Speech-to-script alignment")
struct TranscriptAlignerTests {
    static let scriptText = """
    Good morning everyone, and thank you for joining today's presentation.
    We are going to talk about how small teams ship reliable software.
    [pause]
    ---
    First, let's look at why most release processes break down under pressure.
    The answer is usually communication, not tooling.
    ---
    Finally, I'll share three habits you can start using tomorrow morning.
    """

    static let document = ScriptParser.parse(scriptText)
    static var script: [String] { document.words.map(\.normalized) }

    /// Feeds the transcript word by word, like a live recogniser, and returns the final position.
    func follow(_ spoken: String, aligner: inout TranscriptAligner) -> [Int] {
        let words = Normalizer.words(in: spoken)
        var positions: [Int] = []
        for end in 1...words.count {
            positions.append(aligner.update(transcript: Array(words[..<end])).position)
        }
        return positions
    }

    func index(of word: String, after start: Int = 0) -> Int {
        Self.script[start...].firstIndex(of: word)!
    }

    @Test func cleanReadingTracksEveryWord() {
        var aligner = TranscriptAligner(script: Self.script)
        let spoken = Self.document.words.map(\.display).joined(separator: " ")
        let positions = follow(spoken, aligner: &aligner)
        #expect(positions.last == Self.script.count - 1)
        // Never moves backward.
        #expect(zip(positions, positions.dropFirst()).allSatisfy { $0 <= $1 })
        // Stays within a word or two of the truth throughout.
        for (spokenIndex, position) in positions.enumerated() {
            #expect(abs(position - spokenIndex) <= 1, "word \(spokenIndex) → \(position)")
        }
    }

    @Test func toleratesAdLibsAndFillers() {
        var aligner = TranscriptAligner(script: Self.script)
        let spoken = "um good morning everyone so uh and thank you all so much for joining today's presentation honestly"
        let positions = follow(spoken, aligner: &aligner)
        #expect(positions.last == index(of: "presentation"))
    }

    @Test func toleratesSkippedWords() {
        var aligner = TranscriptAligner(script: Self.script)
        let spoken = "good morning everyone thank you for joining the presentation we are going to talk about small teams ship software"
        let positions = follow(spoken, aligner: &aligner)
        #expect(positions.last == index(of: "software"))
    }

    @Test func toleratesMispronunciationsAndRecogniserSpelling() {
        var aligner = TranscriptAligner(script: Self.script)
        let spoken = "good mornin every one and thank you for joinin todays presentashun"
        let positions = follow(spoken, aligner: &aligner)
        #expect(positions.last == index(of: "presentation"))
    }

    @Test func pausesWhenSpeakerGoesOffScript() {
        var aligner = TranscriptAligner(script: Self.script)
        let spoken = "good morning everyone and thank you for joining"
        let before = follow(spoken, aligner: &aligner).last!
        let rambling = spoken + " before we start can I just say the weather outside is absolutely wild this week"
        let words = Normalizer.words(in: rambling)
        var position = before
        for end in Normalizer.words(in: spoken).count...words.count {
            position = aligner.update(transcript: Array(words[..<end])).position
        }
        #expect(position == before)
    }

    @Test func singleCommonWordDoesNotJumpAhead() {
        var aligner = TranscriptAligner(script: Self.script)
        // "the" appears later in the script; on its own it must not move us there.
        let update = aligner.update(transcript: ["the"])
        #expect(update.position == -1)
    }

    @Test func recoversWhenSpeakerSkipsAWholeSection() {
        var aligner = TranscriptAligner(script: Self.script)
        let spoken = "good morning everyone and thank you for joining today's presentation finally I'll share three habits you can start using tomorrow"
        let positions = follow(spoken, aligner: &aligner)
        #expect(positions.last == index(of: "tomorrow"))
    }

    @Test func volatileResultsCanRewriteTheTail() {
        var aligner = TranscriptAligner(script: Self.script)
        aligner.update(transcript: ["good", "morning", "every"])
        // The recogniser revises its guess; the matches for the tail are replaced.
        let update = aligner.update(transcript: ["good", "morning", "everyone", "and"])
        #expect(update.position == index(of: "and"))
        #expect(aligner.matches[2] == index(of: "everyone"))
        // The transcript can also shrink.
        aligner.update(transcript: ["good", "morning"])
        #expect(aligner.matches.keys.allSatisfy { $0 < 2 })
        #expect(aligner.position == index(of: "and"))
    }

    @Test func resetMovesThePosition() {
        var aligner = TranscriptAligner(script: Self.script)
        let section = Self.document.sections[1].wordRange!.lowerBound
        aligner.reset(to: section - 1)
        let update = aligner.update(transcript: Normalizer.words(in: "first let's look"))
        #expect(update.position == section + 2)
    }

    @Test func simulatedMessyReadingReachesTheEnd() {
        for seed in UInt64(1)...20 {
            var options = TranscriptSimulator.Options()
            options.seed = seed
            options.skipRate = 0.06
            options.adLibRate = 0.06
            options.mispronounceRate = 0.1
            options.fillerRate = 0.05
            let transcript = TranscriptSimulator(options: options).transcript(for: Self.document).map { Normalizer.normalize($0.text) }
            var aligner = TranscriptAligner(script: Self.script)
            var previous = -1
            for end in 1...transcript.count {
                let position = aligner.update(transcript: Array(transcript[..<end])).position
                #expect(position >= previous)
                previous = position
            }
            #expect(aligner.position >= Self.script.count - 3, "seed \(seed) ended at \(aligner.position) of \(Self.script.count)")
        }
    }

    @Test func emptyInputsAreSafe() {
        var empty = TranscriptAligner(script: [])
        #expect(empty.update(transcript: ["hello"]).position == -1)
        var aligner = TranscriptAligner(script: Self.script)
        #expect(aligner.update(transcript: []).position == -1)
        #expect(TranscriptAligner.align(transcript: [], script: Self.script).isEmpty)
    }
}

@Suite("Word similarity")
struct WordSimilarityTests {
    @Test func basics() {
        #expect(WordSimilarity.score("hello", "hello") == 1)
        #expect(WordSimilarity.score("3", "three") == 1)
        #expect(WordSimilarity.score("to", "too") == 0)
        #expect(WordSimilarity.score("colour", "color") >= 0.8)
        #expect(WordSimilarity.score("presen", "presentation") >= 0.8)
        #expect(WordSimilarity.score("photograph", "fotograf") >= 0.72)
        #expect(WordSimilarity.score("morning", "software") < 0.5)
    }

    @Test func normalizer() {
        #expect(Normalizer.normalize("Don't!") == "dont")
        #expect(Normalizer.normalize("Café,") == "cafe")
        #expect(Normalizer.normalize("—") == "")
        #expect(Normalizer.words(in: "  Hello,   World ") == ["hello", "world"])
    }
}
