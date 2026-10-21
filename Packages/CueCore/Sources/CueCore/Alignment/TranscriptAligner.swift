/// Follows a speaker through a script by aligning the recogniser's running transcript to it.
///
/// Every update aligns only the last few transcript words against a window of script
/// around the current position, using local (Smith–Waterman) alignment with fuzzy word
/// scores. That tolerates:
/// - ad-libs: extra transcript words become gaps,
/// - skipped words or lines: script words become cheap gaps,
/// - mispronunciations and recogniser spelling: `WordSimilarity` gives partial credit,
/// - volatile results that rewrite the last words: each update re-reads the tail, so the
///   caller can pass the latest full transcript every time.
///
/// The position only moves forward. Big jumps need more matched words as evidence, and
/// when the speaker has skipped far ahead, a wider recovery search runs after a few
/// updates with no match.
public struct TranscriptAligner: Sendable {
    public struct Configuration: Sendable, Equatable {
        /// How many of the latest transcript words each update looks at.
        public var tailLength = 10
        /// How far behind the current position the window starts.
        public var lookBehind = 3
        /// How far ahead of the current position the window reaches.
        public var lookAhead = 30
        /// Minimum `WordSimilarity` to count as the same word.
        public var matchThreshold = 0.72
        public var matchReward = 2.0
        public var mismatchPenalty = -1.0
        /// Cost of a transcript word with no script counterpart (ad-lib, filler).
        public var transcriptGapPenalty = -0.7
        /// Cost of a script word the speaker skipped.
        public var scriptGapPenalty = -0.5
        /// Forward jumps longer than this need `longJumpMinimumMatches`.
        public var longJumpDistance = 8
        public var longJumpMinimumMatches = 3
        /// Updates in a row with no match before a wider recovery search.
        public var recoveryAfterMisses = 3
        public var recoveryMinimumMatches = 4

        public init() {}
    }

    public struct Update: Sendable, Equatable {
        /// Index of the last script word spoken, or -1 before the first.
        public var position: Int
        /// True when `position` moved forward in this update.
        public var advanced: Bool
    }

    public let script: [String]
    public var configuration: Configuration
    /// Index of the last script word spoken, or -1 before the first.
    public private(set) var position: Int
    /// Transcript word index → script word index, for every transcript word matched so far.
    public private(set) var matches: [Int: Int] = [:]
    private var misses = 0

    public init(script: [String], startingAt position: Int = -1, configuration: Configuration = Configuration()) {
        self.script = script
        self.configuration = configuration
        self.position = min(max(position, -1), script.count - 1)
    }

    public init(document: ScriptDocument, configuration: Configuration = Configuration()) {
        self.init(script: document.words.map(\.normalized), configuration: configuration)
    }

    /// Moves the position, for example after the user scrubs or jumps to a section.
    public mutating func reset(to position: Int) {
        self.position = min(max(position, -1), script.count - 1)
        misses = 0
    }

    /// Feeds the full transcript so far (final words plus the current volatile words).
    @discardableResult
    public mutating func update(transcript: [String]) -> Update {
        matches = matches.filter { $0.key < transcript.count }
        guard !script.isEmpty, !transcript.isEmpty else { return Update(position: position, advanced: false) }

        let tailStart = max(0, transcript.count - configuration.tailLength)
        let tail = Array(transcript[tailStart...])
        let lower = max(0, position - configuration.lookBehind)
        let upper = min(script.count, position + 1 + configuration.lookAhead)

        if let accepted = bestAlignment(tail: tail, tailStart: tailStart, lower: lower, upper: upper, recovery: false) {
            let update = apply(accepted, tailStart: tailStart)
            if update.advanced { return update }
        }

        misses += 1
        if misses >= configuration.recoveryAfterMisses, tail.count >= configuration.recoveryMinimumMatches, upper < script.count,
           let accepted = bestAlignment(tail: tail, tailStart: tailStart, lower: position + 1, upper: script.count, recovery: true) {
            return apply(accepted, tailStart: tailStart)
        }
        return Update(position: position, advanced: false)
    }

    /// Aligns a whole finished transcript in one go (used by the delivery coach).
    public static func align(transcript: [String], script: [String], configuration: Configuration = Configuration()) -> [Int: Int] {
        var aligner = TranscriptAligner(script: script, configuration: configuration)
        guard !transcript.isEmpty else { return [:] }
        for end in 1...transcript.count {
            aligner.update(transcript: Array(transcript[..<end]))
        }
        return aligner.matches
    }

    // MARK: - Alignment

    /// Matched pairs as (tail index, script index).
    private typealias Pairs = [(tail: Int, script: Int)]

    private mutating func apply(_ pairs: Pairs, tailStart: Int) -> Update {
        // Re-aligned words replace earlier guesses; older words outside the aligned
        // stretch keep their matches.
        let alignedStart = tailStart + (pairs.first?.tail ?? 0)
        for key in matches.keys where key >= alignedStart { matches[key] = nil }
        for pair in pairs { matches[tailStart + pair.tail] = pair.script }
        let candidate = pairs.map(\.script).max() ?? position
        let advanced = candidate > position
        position = max(position, candidate)
        if advanced { misses = 0 }
        return Update(position: position, advanced: advanced)
    }

    private func bestAlignment(tail: [String], tailStart: Int, lower: Int, upper: Int, recovery: Bool) -> Pairs? {
        guard lower < upper else { return nil }
        let window = Array(script[lower..<upper])
        let rows = tail.count, columns = window.count
        let width = columns + 1
        var score = [Double](repeating: 0, count: (rows + 1) * width)
        // 0 = stop, 1 = diagonal, 2 = up (transcript gap), 3 = left (script gap)
        var trace = [UInt8](repeating: 0, count: (rows + 1) * width)
        var similarity = [Double](repeating: 0, count: (rows + 1) * width)
        let c = configuration
        var best: (value: Double, cell: Int)?

        for i in 1...rows {
            for j in 1...columns {
                let cell = i * width + j
                let sim = WordSimilarity.score(tail[i - 1], window[j - 1])
                similarity[cell] = sim
                let diagonal = score[cell - width - 1] + (sim >= c.matchThreshold ? c.matchReward * sim : c.mismatchPenalty)
                let up = score[cell - width] + c.transcriptGapPenalty
                let left = score[cell - 1] + c.scriptGapPenalty
                var value = 0.0, direction: UInt8 = 0
                if diagonal > value { value = diagonal; direction = 1 }
                if up > value { value = up; direction = 2 }
                if left > value { value = left; direction = 3 }
                score[cell] = value
                trace[cell] = direction
                guard direction == 1, sim >= c.matchThreshold else { continue }
                // Prefer alignments that end near where we expect the speaker to be.
                let distance = abs((lower + j - 1) - (position + 1))
                let ranked = value - 0.02 * Double(distance) + 0.001 * Double(i)
                if best == nil || ranked > best!.value { best = (ranked, cell) }
            }
        }
        guard let best else { return nil }

        var pairs: Pairs = []
        var cell = best.cell
        while trace[cell] != 0 {
            let i = cell / width, j = cell % width
            switch trace[cell] {
            case 1:
                if similarity[cell] >= c.matchThreshold { pairs.append((i - 1, lower + j - 1)) }
                cell -= width + 1
            case 2: cell -= width
            default: cell -= 1
            }
        }
        pairs.reverse()
        return accept(pairs, tail: tail, recovery: recovery) ? pairs : nil
    }

    private func accept(_ pairs: Pairs, tail: [String], recovery: Bool) -> Bool {
        guard let last = pairs.last else { return false }
        let jump = last.script - position
        // Words already behind the position can't be the evidence for moving forward.
        let fresh = pairs.filter { $0.script > position }.count
        if recovery {
            return fresh >= configuration.recoveryMinimumMatches
        }
        if fresh == 0 {
            // Re-reading what was already matched: keep the matches, don't move.
            return pairs.count >= 2
        }
        if fresh >= 2 {
            return jump <= configuration.longJumpDistance || fresh >= configuration.longJumpMinimumMatches
        }
        // One new word, continuing an alignment through words already matched: the
        // context makes it trustworthy even when it is a little misheard.
        if pairs.count >= 2 {
            let previous = pairs[pairs.count - 2]
            return jump <= 2
                && last.tail >= tail.count - 2
                && last.tail - previous.tail <= 2
                && last.script - previous.script <= 2
        }
        // A single word only counts when it is the very next script word, said just now,
        // and is distinctive enough not to be a coincidence.
        return jump == 1
            && last.tail >= tail.count - 2
            && script[last.script].count >= 3
            && WordSimilarity.score(tail[last.tail], script[last.script]) >= 0.9
    }
}
