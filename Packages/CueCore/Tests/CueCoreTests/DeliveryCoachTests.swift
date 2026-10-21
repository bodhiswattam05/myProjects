import Foundation
import Testing
@testable import CueCore

@Suite("Filler counter")
struct FillerCounterTests {
    @Test func alwaysFillersCountEvenWhenMatched() {
        let counts = FillerCounter.count(words: ["um", "hello", "uhh", "um"], matched: [0])
        #expect(counts == ["um": 2, "uh": 1])
    }

    @Test func contextFillersOnlyCountOffScript() {
        // "like" at 1 is in the script ("I like it"); "like" at 4 and "basically" at 5 aren't.
        let words = ["i", "like", "it", "and", "like", "basically", "yes"]
        let counts = FillerCounter.count(words: words, matched: [0, 1, 2, 6])
        #expect(counts == ["like": 1, "basically": 1])
    }

    @Test func phraseFillers() {
        let words = ["you", "know", "we", "kind", "of", "did", "i", "mean", "it"]
        let counts = FillerCounter.count(words: words, matched: [2, 5, 8])
        #expect(counts == ["you know": 1, "kind of": 1, "i mean": 1])
    }

    @Test func phraseInsideScriptIsNotAFiller() {
        let counts = FillerCounter.count(words: ["you", "know", "this"], matched: [0, 1, 2])
        #expect(counts.isEmpty)
    }

    @Test func empty() {
        #expect(FillerCounter.count(words: [], matched: []).isEmpty)
    }
}

@Suite("Delivery coach")
struct DeliveryCoachTests {
    static let document = ScriptParser.parse("""
    Thanks for watching this short video about our new app.
    ---
    It helps you read a script while looking straight at the camera.
    """)

    func timed(_ text: String, wordsPerMinute: Double = 120, pauseAfter: [Int: Double] = [:]) -> [TimedWord] {
        let step = 60 / wordsPerMinute
        var time = 0.0
        return text.split(separator: " ").enumerated().map { index, word in
            let item = TimedWord(text: String(word), start: time, end: time + step * 0.8)
            time += step + (pauseAfter[index] ?? 0)
            return item
        }
    }

    @Test func paceAndCoverageForACleanRead() {
        let spoken = Self.document.words.map(\.display).joined(separator: " ")
        let transcript = timed(spoken, wordsPerMinute: 120)
        let report = DeliveryCoach.analyze(transcript: transcript, document: Self.document, targetWordsPerMinute: 140, duration: 12)
        #expect(report.wordsSpoken == Self.document.words.count)
        #expect(abs(report.actualWordsPerMinute - 120) < 8)
        #expect(report.scriptCoverage > 0.95)
        #expect(report.offScript.isEmpty)
        #expect(report.fillerCount == 0)
        #expect(report.longestPauses.isEmpty)
    }

    @Test func findsLongestPausesInOrder() {
        let transcript = timed("one two three four five", pauseAfter: [0: 1.2, 2: 2.5, 3: 0.3])
        let pauses = DeliveryCoach.longestPauses(in: transcript)
        #expect(pauses.map(\.afterWord) == ["three", "one"])
        #expect(pauses.first!.duration > pauses.last!.duration)
    }

    @Test func detectsOffScriptRunWithSection() {
        let spoken = "Thanks for watching this short video about our new app um so before I go on my dog just walked in sorry It helps you read a script while looking straight at the camera"
        let report = DeliveryCoach.analyze(transcript: timed(spoken), document: Self.document, targetWordsPerMinute: 140, duration: 20)
        #expect(report.offScript.count == 1)
        #expect(report.offScript.first?.text.contains("dog") == true)
        #expect(report.offScript.first?.sectionIndex == 0)
        #expect(report.fillers["um"] == 1)
        #expect(report.fillers["so"] == 1)
    }

    @Test func simulatedTakeProducesSensibleReport() {
        var options = TranscriptSimulator.Options()
        options.fillerRate = 0.1
        options.longPauseRate = 0.1
        let transcript = TranscriptSimulator(options: options).transcript(for: Self.document)
        let report = DeliveryCoach.analyze(transcript: transcript, document: Self.document, targetWordsPerMinute: 140, duration: transcript.last!.end)
        #expect(report.scriptCoverage > 0.7)
        #expect(report.actualWordsPerMinute > 80)
    }

    @Test func reportIsCodable() throws {
        let report = DeliveryCoach.analyze(transcript: timed("Thanks for watching"), document: Self.document, targetWordsPerMinute: 140, duration: 2)
        let data = try JSONEncoder().encode(report)
        #expect(try JSONDecoder().decode(DeliveryReport.self, from: data) == report)
    }
}

@Suite("Scroll spring")
struct ScrollSpringTests {
    @Test func settlesOnTargetWithoutOvershoot() {
        var spring = ScrollSpring()
        var maximum = 0.0
        for _ in 0..<240 {
            maximum = max(maximum, spring.step(toward: 200, deltaTime: 1.0 / 60))
        }
        #expect(abs(spring.position - 200) < 0.5)
        #expect(maximum <= 200)
    }

    @Test func neverMovesBackwardUnlessAllowed() {
        var spring = ScrollSpring(position: 100)
        spring.step(toward: 50, deltaTime: 0.5)
        #expect(spring.position == 100)
        var reversible = ScrollSpring(position: 100, allowsReverse: true)
        for _ in 0..<120 { reversible.step(toward: 50, deltaTime: 1.0 / 60) }
        #expect(abs(reversible.position - 50) < 1)
    }

    @Test func speedIsCapped() {
        var spring = ScrollSpring(maximumSpeed: 300)
        spring.step(toward: 10_000, deltaTime: 0.25)
        #expect(spring.position <= 300 * 0.25 + 0.001)
    }
}
