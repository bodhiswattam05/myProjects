/// One recognised word with its timing in the take, in seconds from the start.
public struct TimedWord: Sendable, Equatable, Codable {
    public var text: String
    public var start: Double
    public var end: Double

    public init(text: String, start: Double, end: Double) {
        self.text = text
        self.start = start
        self.end = end
    }
}

/// Neutral facts about one take. Not a score.
public struct DeliveryReport: Sendable, Equatable, Codable {
    public struct Pause: Sendable, Equatable, Codable {
        public var start: Double
        public var duration: Double
        /// The last word said before the pause, for context.
        public var afterWord: String?
    }

    public struct OffScript: Sendable, Equatable, Codable {
        public var start: Double
        public var end: Double
        /// What was said, as recognised.
        public var text: String
        /// Section the speaker was in, if known.
        public var sectionIndex: Int?
    }

    public var duration: Double
    public var wordsSpoken: Int
    public var targetWordsPerMinute: Int
    /// Words per minute over the time actually spent speaking (first word to last).
    public var actualWordsPerMinute: Double
    /// Share of script words the speaker said, 0...1.
    public var scriptCoverage: Double
    public var longestPauses: [Pause]
    public var offScript: [OffScript]
    public var fillerCount: Int
    /// Filler word → count, for words that appeared at least once.
    public var fillers: [String: Int]
}

public enum DeliveryCoach {
    /// Gaps between words at least this long count as pauses.
    public static let minimumPause = 1.0
    /// Runs of at least this many unmatched words count as going off script.
    public static let minimumOffScriptRun = 4

    public static func analyze(
        transcript: [TimedWord],
        document: ScriptDocument,
        targetWordsPerMinute: Int,
        duration: Double
    ) -> DeliveryReport {
        let normalized = transcript.map { Normalizer.normalize($0.text) }
        let script = document.words.map(\.normalized)
        let matches = TranscriptAligner.align(transcript: normalized, script: script)
        let fillers = FillerCounter.count(words: normalized, matched: Set(matches.keys))

        var speakingTime = 0.0
        if let first = transcript.first, let last = transcript.last {
            speakingTime = max(0, last.end - first.start)
        }
        let wordsPerMinute = speakingTime > 0 ? Double(transcript.count) / speakingTime * 60 : 0
        let coverage = script.isEmpty ? 0 : Double(Set(matches.values).count) / Double(script.count)

        return DeliveryReport(
            duration: duration,
            wordsSpoken: transcript.count,
            targetWordsPerMinute: targetWordsPerMinute,
            actualWordsPerMinute: wordsPerMinute,
            scriptCoverage: coverage,
            longestPauses: longestPauses(in: transcript),
            offScript: offScriptRuns(transcript: transcript, normalized: normalized, matches: matches, document: document),
            fillerCount: fillers.values.reduce(0, +),
            fillers: fillers
        )
    }

    static func longestPauses(in transcript: [TimedWord], limit: Int = 3) -> [DeliveryReport.Pause] {
        guard transcript.count > 1 else { return [] }
        var pauses: [DeliveryReport.Pause] = []
        for index in 1..<transcript.count {
            let gap = transcript[index].start - transcript[index - 1].end
            if gap >= minimumPause {
                pauses.append(.init(start: transcript[index - 1].end, duration: gap, afterWord: transcript[index - 1].text))
            }
        }
        return Array(pauses.sorted { $0.duration > $1.duration }.prefix(limit))
    }

    static func offScriptRuns(
        transcript: [TimedWord],
        normalized: [String],
        matches: [Int: Int],
        document: ScriptDocument
    ) -> [DeliveryReport.OffScript] {
        var runs: [DeliveryReport.OffScript] = []
        var runStart: Int?
        var lastSection: Int?

        func close(at end: Int) {
            guard let start = runStart else { return }
            runStart = nil
            // Fillers alone ("um, uh, like, so") aren't going off script.
            let words = (start..<end).filter { !FillerCounter.isFiller(normalized[$0]) }
            guard words.count >= minimumOffScriptRun else { return }
            runs.append(.init(
                start: transcript[start].start,
                end: transcript[end - 1].end,
                text: transcript[start..<end].map(\.text).joined(separator: " "),
                sectionIndex: lastSection
            ))
        }

        for index in transcript.indices {
            if let scriptIndex = matches[index] {
                close(at: index)
                lastSection = document.sectionIndex(forWord: scriptIndex)
            } else if runStart == nil {
                runStart = index
            }
        }
        close(at: transcript.count)
        return runs
    }
}

/// Counts filler words. "um" and "uh" always count. Words that are also ordinary
/// English ("like", "basically", "so", "actually") only count when the aligner
/// didn't match them to the script, so a script that says "I like it" isn't penalised.
public enum FillerCounter {
    public static let alwaysFillers: Set<String> = ["um", "umm", "uh", "uhh", "er", "erm", "ah", "hmm", "mm"]
    public static let contextFillers: Set<String> = ["like", "basically", "actually", "literally", "so", "right"]
    /// Two-word fillers, matched on consecutive unmatched words.
    public static let phraseFillers: [[String]] = [["you", "know"], ["i", "mean"], ["kind", "of"], ["sort", "of"]]

    public static func isFiller(_ word: String) -> Bool {
        alwaysFillers.contains(word) || contextFillers.contains(word)
    }

    /// - Parameters:
    ///   - words: normalized transcript words
    ///   - matched: indices of transcript words the aligner matched to the script
    public static func count(words: [String], matched: Set<Int>) -> [String: Int] {
        var counts: [String: Int] = [:]
        var index = 0
        while index < words.count {
            let word = words[index]
            if alwaysFillers.contains(word) {
                counts[canonical(word), default: 0] += 1
                index += 1
                continue
            }
            if !matched.contains(index) {
                if let phrase = phraseFillers.first(where: { phrase in
                    index + phrase.count <= words.count
                        && zip(phrase.indices, phrase).allSatisfy { offset, part in
                            words[index + offset] == part && !matched.contains(index + offset)
                        }
                }) {
                    counts[phrase.joined(separator: " "), default: 0] += 1
                    index += phrase.count
                    continue
                }
                if contextFillers.contains(word) {
                    counts[word, default: 0] += 1
                }
            }
            index += 1
        }
        return counts
    }

    private static func canonical(_ word: String) -> String {
        switch word {
        case "umm": "um"
        case "uhh": "uh"
        case "erm": "er"
        default: word
        }
    }
}
