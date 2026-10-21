import AVFoundation
import CueCore
import Foundation
import Speech

// MARK: - SpeechAnalyzer (iOS 26)

/// Uses `SpeechAnalyzer` + `SpeechTranscriber`, the on-device engine introduced in iOS 26
/// (WWDC25 session 277). Runs fully offline once iOS has installed the language model.
@MainActor
final class AnalyzerSpeechEngine: SpeechEngine {
    private let locale: Locale
    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var tasks: [Task<Void, Never>] = []

    init(locale: Locale) {
        self.locale = locale
    }

    static func availability(for locale: Locale) async -> SpeechAvailability {
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            return .unsupportedLanguage
        }
        let wanted = supported.identifier(.bcp47)
        // TODO: VERIFY API — compiles against the iOS 26.5 SDK; confirm on a device that a
        // model downloaded for Dictation shows up in `installedLocales` (airplane-mode check).
        let installed = await SpeechTranscriber.installedLocales
        return installed.contains { $0.identifier(.bcp47) == wanted } ? .ready : .needsModel
    }

    static func installModel(for locale: Locale) async throws {
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw SpeechServiceError.notReady(.unsupportedLanguage)
        }
        let transcriber = makeTranscriber(locale: supported)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }

    private static func makeTranscriber(locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )
    }

    func start(_ audio: AsyncStream<AudioChunk>) async throws -> AsyncStream<[TimedWord]> {
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw SpeechServiceError.notReady(.unsupportedLanguage)
        }
        let transcriber = Self.makeTranscriber(locale: supported)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw SpeechServiceError.notReady(.unavailable)
        }

        let (inputs, inputContinuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let (output, outputContinuation) = AsyncStream.makeStream(of: [TimedWord].self, bufferingPolicy: .bufferingNewest(1))

        let results = Task.detached {
            var finals: [TimedWord] = []
            do {
                for try await result in transcriber.results {
                    let words = Self.timedWords(in: result.text)
                    if result.isFinal {
                        finals.append(contentsOf: words)
                        outputContinuation.yield(finals)
                    } else {
                        outputContinuation.yield(finals + words)
                    }
                }
            } catch {
                // The stream ends with an error when the analyzer is cancelled; nothing to report.
            }
            outputContinuation.finish()
        }

        let target = UncheckedBox(format)
        let feed = Task.detached {
            let converter = AudioFormatConverter(output: target.value)
            for await chunk in audio {
                if let converted = converter.convert(chunk.buffer) {
                    inputContinuation.yield(AnalyzerInput(buffer: converted))
                }
            }
            inputContinuation.finish()
        }

        try await analyzer.start(inputSequence: inputs)
        self.analyzer = analyzer
        self.inputContinuation = inputContinuation
        tasks = [results, feed]
        return output
    }

    func stop() async {
        inputContinuation?.finish()
        inputContinuation = nil
        tasks.forEach { $0.cancel() }
        tasks = []
        if let analyzer {
            await analyzer.cancelAndFinishNow()
        }
        analyzer = nil
    }

    /// Words with times from the transcriber's attributed text. A word takes the start of
    /// the run it begins in and the end of the run it finishes in.
    nonisolated static func timedWords(in text: AttributedString) -> [TimedWord] {
        var words: [TimedWord] = []
        var current = ""
        var start = 0.0
        var end = 0.0
        for run in text.runs {
            // TODO: VERIFY API — `audioTimeRange` is the documented accessor for
            // AttributeScopes.SpeechAttributes.TimeRangeAttribute; confirm on device.
            let range = run.audioTimeRange
            let runStart = range.map { $0.start.seconds } ?? end
            let runEnd = range.map { $0.end.seconds } ?? end
            for character in text[run.range].characters {
                if character.isWhitespace {
                    if !current.isEmpty {
                        words.append(TimedWord(text: current, start: start, end: end))
                        current = ""
                    }
                } else {
                    if current.isEmpty { start = runStart }
                    current.append(character)
                    end = runEnd
                }
            }
        }
        if !current.isEmpty {
            words.append(TimedWord(text: current, start: start, end: end))
        }
        return words
    }
}

// MARK: - SFSpeechRecognizer fallback

/// The older recogniser, used only when `SpeechTranscriber` doesn't support the device or
/// language. `requiresOnDeviceRecognition` guarantees audio never leaves the device.
@MainActor
final class LegacySpeechEngine: SpeechEngine {
    private let locale: Locale
    private var session: LegacyRecognitionSession?
    private var feed: Task<Void, Never>?

    init(locale: Locale) {
        self.locale = locale
    }

    static func availability(for locale: Locale) -> SpeechAvailability {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else { return .notAuthorized }
        guard let recognizer = SFSpeechRecognizer(locale: locale) else { return .unsupportedLanguage }
        guard recognizer.supportsOnDeviceRecognition, recognizer.isAvailable else { return .unavailable }
        return .ready
    }

    func start(_ audio: AsyncStream<AudioChunk>) async throws -> AsyncStream<[TimedWord]> {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.supportsOnDeviceRecognition else {
            throw SpeechServiceError.notReady(.unavailable)
        }
        let (output, continuation) = AsyncStream.makeStream(of: [TimedWord].self, bufferingPolicy: .bufferingNewest(1))
        let session = LegacyRecognitionSession(recognizer: recognizer, output: continuation)
        session.begin()
        self.session = session
        feed = Task.detached {
            for await chunk in audio {
                session.append(chunk.buffer)
            }
            session.finish()
        }
        return output
    }

    func stop() async {
        feed?.cancel()
        feed = nil
        session?.finish()
        session = nil
    }
}

/// Owns the current recognition request. `SFSpeechRecognizer` tasks end after about a
/// minute, so when one finishes a new one starts and its times are offset to match.
/// All mutable state is guarded by `lock`; callbacks arrive on the recogniser's queue.
private final class LegacyRecognitionSession: @unchecked Sendable {
    private let recognizer: SFSpeechRecognizer
    private let output: AsyncStream<[TimedWord]>.Continuation
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var finals: [TimedWord] = []
    private var latest: [TimedWord] = []
    private var audioSeconds = 0.0
    private var requestOffset = 0.0
    private var generation = 0
    private var isFinished = false

    init(recognizer: SFSpeechRecognizer, output: AsyncStream<[TimedWord]>.Continuation) {
        self.recognizer = recognizer
        self.output = output
    }

    func begin() {
        lock.lock()
        defer { lock.unlock() }
        startRequestLocked()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinished else { return }
        request?.append(buffer)
        audioSeconds += Double(buffer.frameLength) / buffer.format.sampleRate
    }

    func finish() {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinished else { return }
        isFinished = true
        request?.endAudio()
        task?.finish()
        output.finish()
    }

    private func startRequestLocked() {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        generation += 1
        let generation = generation
        requestOffset = audioSeconds
        self.request = request
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            self?.handle(result: result, error: error, generation: generation)
        }
    }

    private func handle(result: SFSpeechRecognitionResult?, error: (any Error)?, generation: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard generation == self.generation, !isFinished else { return }
        if let result {
            let offset = requestOffset
            latest = result.bestTranscription.segments.map {
                TimedWord(text: $0.substring, start: offset + $0.timestamp, end: offset + $0.timestamp + $0.duration)
            }
            output.yield(finals + latest)
        }
        if error != nil || result?.isFinal == true {
            // Keep what we heard and carry on with a fresh request.
            finals.append(contentsOf: latest)
            latest = []
            request?.endAudio()
            startRequestLocked()
        }
    }
}
