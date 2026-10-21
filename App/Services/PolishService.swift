import CueCore
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The three rewrite actions offered on selected text.
enum PolishAction: Hashable, Identifiable {
    /// Shorter sentences, contractions, words that are easy to say.
    case makeSpoken
    /// Cut to roughly this many seconds at the script's pace.
    case trim(seconds: Int)
    /// Add `[pause]` and `[breathe]` where a speaker would naturally stop.
    case addPauses

    var id: String {
        switch self {
        case .makeSpoken: "spoken"
        case let .trim(seconds): "trim-\(seconds)"
        case .addPauses: "pauses"
        }
    }

    var title: String {
        switch self {
        case .makeSpoken: String(localized: "Make it sound spoken")
        case let .trim(seconds): String(localized: "Trim to \(seconds) seconds")
        case .addPauses: String(localized: "Add pause marks")
        }
    }
}

enum PolishError: LocalizedError {
    case unavailable
    case nothingChanged
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: String(localized: "Script polish isn't available on this device.")
        case .nothingChanged: String(localized: "No changes to suggest for this text.")
        case let .failed(message): message
        }
    }
}

/// Rewrites script text on device. Results are always shown as a diff for the user to
/// accept or reject; nothing is ever replaced without asking.
@MainActor
protocol ScriptPolishing: AnyObject {
    /// When false the feature is hidden entirely, not shown disabled.
    var isAvailable: Bool { get }
    func polish(_ text: String, action: PolishAction, wordsPerMinute: Int) async throws -> String
}

enum PolishPrompt {
    static let instructions = """
    You edit teleprompter scripts that someone will read aloud on camera.
    Keep the speaker's meaning, facts, names and numbers. Keep the same language.
    The script uses markup: [pause] and [breathe] are delivery cues, *words* are emphasis,
    // starts a private note, and --- on its own line separates sections. Keep existing markup.
    Reply with only the rewritten text. No introduction, no explanation, no quotation marks.
    """

    static func prompt(for text: String, action: PolishAction, wordsPerMinute: Int) -> String {
        switch action {
        case .makeSpoken:
            return """
            Rewrite this so it sounds natural when spoken: shorter sentences, contractions, \
            everyday words, no long lists. Don't add new ideas.

            \(text)
            """
        case let .trim(seconds):
            let words = max(5, seconds * wordsPerMinute / 60)
            return """
            Shorten this to about \(words) words, so it takes about \(seconds) seconds to say. \
            Keep the most important points and the closing line.

            \(text)
            """
        case .addPauses:
            return """
            Return this text unchanged except for adding [pause] where a speaker should stop \
            for effect and [breathe] before long sentences. Don't change any words.

            \(text)
            """
        }
    }

    /// Removes wrapping quotes or a stray "Here's the rewrite:" line some models add.
    static func clean(_ output: String) -> String {
        var text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = text.split(separator: "\n", maxSplits: 1).first,
           first.lowercased().hasPrefix("here"), first.hasSuffix(":") {
            text = String(text.dropFirst(first.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for (open, close) in [("\"", "\""), ("“", "”")] where text.hasPrefix(open) && text.hasSuffix(close) && text.count > 1 {
            text = String(text.dropFirst().dropLast())
        }
        return text
    }
}

/// Apple's on-device Foundation Models (iOS 26). Pinned to `SystemLanguageModel.default`,
/// which runs locally; no cloud or Private Cloud Compute model is ever used.
@MainActor
final class FoundationModelsPolisher: ScriptPolishing {
    var isAvailable: Bool {
        #if canImport(FoundationModels)
        if case .available = SystemLanguageModel.default.availability { return true }
        #endif
        return false
    }

    func polish(_ text: String, action: PolishAction, wordsPerMinute: Int) async throws -> String {
        #if canImport(FoundationModels)
        guard isAvailable else { throw PolishError.unavailable }
        let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: PolishPrompt.instructions)
        do {
            let response = try await session.respond(to: PolishPrompt.prompt(for: text, action: action, wordsPerMinute: wordsPerMinute))
            let result = PolishPrompt.clean(response.content)
            guard !result.isEmpty, !WordDiff.isUnchanged(text, result) else { throw PolishError.nothingChanged }
            return result
        } catch let error as PolishError {
            throw error
        } catch {
            throw PolishError.failed(String(localized: "Couldn't rewrite this text. Try a shorter selection."))
        }
        #else
        throw PolishError.unavailable
        #endif
    }
}

/// Predictable rewrites for previews, tests and the Simulator's Debug screen.
@MainActor
final class SimulatedPolisher: ScriptPolishing {
    let isAvailable = true

    func polish(_ text: String, action: PolishAction, wordsPerMinute: Int) async throws -> String {
        try? await Task.sleep(for: .milliseconds(400))
        let result: String
        switch action {
        case .makeSpoken:
            result = text
                .replacingOccurrences(of: "we are", with: "we're")
                .replacingOccurrences(of: "We are", with: "We're")
                .replacingOccurrences(of: "do not", with: "don't")
                .replacingOccurrences(of: "it is", with: "it's")
                .replacingOccurrences(of: "It is", with: "It's")
                .replacingOccurrences(of: ", and ", with: ". And ")
        case let .trim(seconds):
            let words = text.split(whereSeparator: \.isWhitespace)
            result = words.prefix(max(5, seconds * wordsPerMinute / 60)).joined(separator: " ")
        case .addPauses:
            result = text
                .replacingOccurrences(of: ". ", with: ". [pause] ")
                .replacingOccurrences(of: "? ", with: "? [pause] ")
        }
        guard !WordDiff.isUnchanged(text, result) else { throw PolishError.nothingChanged }
        return result
    }
}
