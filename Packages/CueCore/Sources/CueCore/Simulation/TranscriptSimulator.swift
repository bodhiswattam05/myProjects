/// Makes a believable, messy transcript from a script, so voice-paced scrolling and the
/// delivery coach can be tested without speaking (Debug screen, unit tests, previews).
public struct TranscriptSimulator: Sendable {
    public struct Options: Sendable, Equatable {
        public var wordsPerMinute: Double = 140
        /// Chance that a script word is skipped.
        public var skipRate: Double = 0.04
        /// Chance of an ad-libbed word after a script word.
        public var adLibRate: Double = 0.04
        /// Chance a word comes through misspelled or mispronounced.
        public var mispronounceRate: Double = 0.05
        /// Chance of "um"/"uh" before a word.
        public var fillerRate: Double = 0.03
        /// Chance of a long (2–3.5 s) pause after a word.
        public var longPauseRate: Double = 0.01
        public var seed: UInt64 = 7

        public init() {}

        public static let clean: Options = {
            var options = Options()
            options.skipRate = 0
            options.adLibRate = 0
            options.mispronounceRate = 0
            options.fillerRate = 0
            options.longPauseRate = 0
            return options
        }()
    }

    static let adLibs = ["really", "okay", "honestly", "right", "so", "and", "well"]
    static let fillers = ["um", "uh"]

    public var options: Options

    public init(options: Options = Options()) {
        self.options = options
    }

    public func transcript(for document: ScriptDocument) -> [TimedWord] {
        var random = SplitMix64(seed: options.seed)
        let wordDuration = 60 / max(options.wordsPerMinute, 1)
        var time = 0.4
        var output: [TimedWord] = []

        func say(_ text: String) {
            let length = wordDuration * (0.85 + random.unit() * 0.3)
            output.append(TimedWord(text: text, start: time, end: time + length * 0.9))
            time += length
        }

        for word in document.words {
            if random.unit() < options.fillerRate { say(Self.fillers[random.index(Self.fillers.count)]) }
            if random.unit() < options.skipRate { continue }
            var text = word.display.filter { $0.isLetter || $0.isNumber || $0 == "'" }
            if text.isEmpty { continue }
            if text.count > 4, random.unit() < options.mispronounceRate {
                text = String(text.dropLast())
            }
            say(text)
            if random.unit() < options.adLibRate { say(Self.adLibs[random.index(Self.adLibs.count)]) }
            if random.unit() < options.longPauseRate { time += 2 + random.unit() * 1.5 }
        }
        return output
    }
}

/// Small deterministic generator so simulated transcripts are repeatable.
struct SplitMix64: Sendable {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func index(_ count: Int) -> Int { Int(next() % UInt64(count)) }
}
