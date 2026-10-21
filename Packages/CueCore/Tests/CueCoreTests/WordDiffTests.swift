import Testing
@testable import CueCore

@Suite("Word diff")
struct WordDiffTests {
    @Test func identicalTextsAreAllSame() {
        let tokens = WordDiff.tokens(from: "Hello  there\nworld", to: "Hello there world")
        #expect(tokens == [.init(kind: .same, text: "Hello there world")])
        #expect(WordDiff.isUnchanged("a b", "a  b"))
    }

    @Test func replacementShowsRemovalThenAddition() {
        let tokens = WordDiff.tokens(from: "We are going to start now.", to: "We're going to start now.")
        #expect(tokens == [
            .init(kind: .removed, text: "We are"),
            .init(kind: .added, text: "We're"),
            .init(kind: .same, text: "going to start now.")
        ])
    }

    @Test func insertionsAndDeletions() {
        let tokens = WordDiff.tokens(from: "one two three four", to: "one three [pause] four five")
        #expect(tokens == [
            .init(kind: .same, text: "one"),
            .init(kind: .removed, text: "two"),
            .init(kind: .same, text: "three"),
            .init(kind: .added, text: "[pause]"),
            .init(kind: .same, text: "four"),
            .init(kind: .added, text: "five")
        ])
    }

    @Test func emptySides() {
        #expect(WordDiff.tokens(from: "", to: "") == [])
        #expect(WordDiff.tokens(from: "", to: "new words") == [.init(kind: .added, text: "new words")])
        #expect(WordDiff.tokens(from: "old words", to: "") == [.init(kind: .removed, text: "old words")])
    }
}
