import Testing
@testable import CueCore

@Suite("Read time estimator")
struct ReadTimeEstimatorTests {
    @Test func defaultPaceIs140() {
        #expect(ReadTimeEstimator().wordsPerMinute == 140)
    }

    @Test func wordsOnly() {
        let estimator = ReadTimeEstimator(wordsPerMinute: 120)
        let text = Array(repeating: "word", count: 240).joined(separator: " ")
        #expect(abs(estimator.seconds(for: text) - 120) < 0.001)
    }

    @Test func cuesAndBreaksAddTime() {
        let estimator = ReadTimeEstimator(wordsPerMinute: 60)
        // 2 words = 2 s, pause 1.5, breathe 0.75, one break 1.0
        let seconds = estimator.seconds(for: "One [pause] [breathe]\n---\nTwo")
        #expect(abs(seconds - 5.25) < 0.001)
    }

    @Test func notesDoNotCount() {
        let estimator = ReadTimeEstimator(wordsPerMinute: 60)
        #expect(abs(estimator.seconds(for: "One // a long note that is not read aloud") - 1) < 0.001)
    }

    @Test func paceIsClamped() {
        #expect(ReadTimeEstimator(wordsPerMinute: 5).wordsPerMinute == 60)
        #expect(ReadTimeEstimator(wordsPerMinute: 900).wordsPerMinute == 260)
    }

    @Test(arguments: [
        (0.0, "0 sec"), (44.6, "45 sec"), (60, "1 min"), (130, "2 min 10 sec"),
        (3600, "1 hr"), (3900, "1 hr 5 min")
    ])
    func formatting(seconds: Double, expected: String) {
        #expect(ReadTimeEstimator.format(seconds: seconds) == expected)
    }
}
