/// Estimates how long a script takes to read aloud at a given pace.
public struct ReadTimeEstimator: Sendable, Equatable {
    public static let defaultWordsPerMinute = 140
    public static let wordsPerMinuteRange = 60...260

    public var wordsPerMinute: Int
    /// Seconds added for each `[pause]`.
    public var pauseSeconds: Double = 1.5
    /// Seconds added for each `[breathe]`.
    public var breatheSeconds: Double = 0.75
    /// Seconds added for each `---` section break.
    public var sectionBreakSeconds: Double = 1.0

    public init(wordsPerMinute: Int = ReadTimeEstimator.defaultWordsPerMinute) {
        self.wordsPerMinute = min(max(wordsPerMinute, Self.wordsPerMinuteRange.lowerBound), Self.wordsPerMinuteRange.upperBound)
    }

    public func seconds(for document: ScriptDocument) -> Double {
        seconds(forWordCount: document.words.count)
            + Double(document.pauseCount) * pauseSeconds
            + Double(document.breatheCount) * breatheSeconds
            + Double(document.sectionBreakCount) * sectionBreakSeconds
    }

    public func seconds(forWordCount count: Int) -> Double {
        Double(count) / Double(wordsPerMinute) * 60
    }

    public func seconds(for source: String) -> Double {
        seconds(for: ScriptParser.parse(source))
    }

    /// Plain, sentence-case duration such as "45 sec", "2 min 10 sec" or "1 hr 5 min".
    public static func format(seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total) sec" }
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return minutes > 0 ? "\(hours) hr \(minutes) min" : "\(hours) hr" }
        return secs > 0 ? "\(minutes) min \(secs) sec" : "\(minutes) min"
    }
}
