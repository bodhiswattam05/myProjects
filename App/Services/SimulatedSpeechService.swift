import CueCore
import Foundation

/// Plays a fake transcript in real time, so voice pacing can be tested without speaking.
/// Used by the Debug screen, previews, the Simulator and UI tests.
@MainActor
final class SimulatedSpeechService: SpeechRecognizing {
    private var document: ScriptDocument
    private var options: TranscriptSimulator.Options
    private var playback: Task<Void, Never>?
    private var startOffset: Double = 0
    private var isConfigured = false

    init(document: ScriptDocument = .empty, options: TranscriptSimulator.Options = .init()) {
        self.document = document
        self.options = options
    }

    /// Sets what the next `startListening` will "say".
    func configure(document: ScriptDocument, options: TranscriptSimulator.Options) {
        self.document = document
        self.options = options
        isConfigured = true
    }

    /// Reads the script being prompted, unless the Debug screen already chose one.
    func prepare(for document: ScriptDocument) {
        guard !isConfigured else { return }
        self.document = document
    }

    /// Starts playback partway in, after the user scrubs or jumps.
    func skip(toScriptWord index: Int) {
        startOffset = Double(max(0, index)) * 60 / max(options.wordsPerMinute, 1)
    }

    func availability() async -> SpeechAvailability { .ready }
    func installModel() async throws {}

    func startListening() async throws -> AsyncStream<[TimedWord]> {
        playback?.cancel()
        let transcript = TranscriptSimulator(options: options).transcript(for: document)
        let offset = startOffset
        let (stream, continuation) = AsyncStream.makeStream(of: [TimedWord].self, bufferingPolicy: .bufferingNewest(1))
        playback = Task {
            let clock = ContinuousClock()
            let began = clock.now
            var spoken: [TimedWord] = []
            for word in transcript where word.end > offset {
                let due = began + .milliseconds(Int((word.end - offset) * 1000))
                try? await clock.sleep(until: due)
                if Task.isCancelled { break }
                spoken.append(word)
                continuation.yield(spoken)
            }
            continuation.finish()
        }
        return stream
    }

    func startTranscribing(_ audio: AsyncStream<AudioChunk>) async throws -> AsyncStream<[TimedWord]> {
        try await startListening()
    }

    func stop() async {
        playback?.cancel()
        playback = nil
        startOffset = 0
    }
}
