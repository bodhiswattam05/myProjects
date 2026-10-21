import AVFoundation
import CueCore
import Foundation

/// Whether voice pacing can run right now, and if not, what the user can do about it.
enum SpeechAvailability: Equatable, Sendable {
    case ready
    /// The on-device speech model isn't installed yet. iOS downloads it once, like Dictation.
    case needsModel
    case notAuthorized
    case unsupportedLanguage
    case unavailable

    var isReady: Bool { self == .ready }

    /// Plain message for the prompter when voice pacing can't start.
    var message: String {
        switch self {
        case .ready:
            String(localized: "Voice pacing is ready.")
        case .needsModel:
            String(localized: "Voice pacing needs a speech model that iOS downloads once. Connect to the internet and try again. Scrolling at a steady speed for now.")
        case .notAuthorized:
            String(localized: "Voice pacing needs microphone and speech recognition access. You can allow them in Settings. Scrolling at a steady speed for now.")
        case .unsupportedLanguage:
            String(localized: "Voice pacing isn't available for your device language yet. Scrolling at a steady speed for now.")
        case .unavailable:
            String(localized: "Voice pacing isn't available on this device. Scrolling at a steady speed for now.")
        }
    }
}

/// An audio buffer that can cross into the recogniser. Each buffer is handed off once and
/// never touched again by the sender, which is what makes the unchecked conformance safe.
struct AudioChunk: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
}

/// Carries a value whose type isn't marked `Sendable` (some AVFoundation classes) into a
/// task that becomes its only user.
struct UncheckedBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

/// On-device speech recognition. Every implementation must work offline once its model
/// is installed and must never send audio off the device.
@MainActor
protocol SpeechRecognizing: AnyObject {
    func availability() async -> SpeechAvailability
    /// Asks iOS to download the speech model. The only network use in Cue, and it's done by the system.
    func installModel() async throws
    /// Listens to the microphone. Each element is the whole transcript so far, final words
    /// followed by the current best guess for the words still being spoken.
    func startListening() async throws -> AsyncStream<[TimedWord]>
    /// Transcribes audio you provide (the recording's own microphone stream).
    func startTranscribing(_ audio: AsyncStream<AudioChunk>) async throws -> AsyncStream<[TimedWord]>
    func stop() async
    /// Tells the service which script is about to be read. Only the simulated service uses it.
    func prepare(for document: ScriptDocument)
}

extension SpeechRecognizing {
    func prepare(for document: ScriptDocument) {}
}

enum SpeechServiceError: LocalizedError {
    case notReady(SpeechAvailability)
    case audioInputUnavailable

    var errorDescription: String? {
        switch self {
        case let .notReady(availability): availability.message
        case .audioInputUnavailable: String(localized: "The microphone isn't available right now.")
        }
    }
}

/// Picks the best on-device engine: `SpeechAnalyzer` (iOS 26) when the device and language
/// support it, otherwise `SFSpeechRecognizer` with on-device recognition required.
@MainActor
final class LiveSpeechService: SpeechRecognizing {
    private let locale: Locale
    private var engine: (any SpeechEngine)?
    private let microphone = MicrophoneStream()

    init(locale: Locale = .current) {
        self.locale = locale
    }

    func availability() async -> SpeechAvailability {
        guard await PermissionCenter.microphoneAndSpeechGranted() else { return .notAuthorized }
        let analyzer = await AnalyzerSpeechEngine.availability(for: locale)
        if analyzer == .ready { return .ready }
        let legacy = LegacySpeechEngine.availability(for: locale)
        if legacy == .ready { return .ready }
        // Prefer the analyzer's answer: it can say "download the model", the legacy one can't.
        return analyzer == .unavailable ? legacy : analyzer
    }

    func installModel() async throws {
        try await AnalyzerSpeechEngine.installModel(for: locale)
    }

    func startListening() async throws -> AsyncStream<[TimedWord]> {
        let audio = try microphone.start()
        return try await startTranscribing(audio)
    }

    func startTranscribing(_ audio: AsyncStream<AudioChunk>) async throws -> AsyncStream<[TimedWord]> {
        await stopEngine()
        let engine: any SpeechEngine
        if await AnalyzerSpeechEngine.availability(for: locale) == .ready {
            engine = AnalyzerSpeechEngine(locale: locale)
        } else if LegacySpeechEngine.availability(for: locale) == .ready {
            engine = LegacySpeechEngine(locale: locale)
        } else {
            microphone.stop()
            throw SpeechServiceError.notReady(await availability())
        }
        self.engine = engine
        return try await engine.start(audio)
    }

    func stop() async {
        microphone.stop()
        await stopEngine()
    }

    private func stopEngine() async {
        await engine?.stop()
        engine = nil
    }
}

/// One recogniser backend.
@MainActor
protocol SpeechEngine: AnyObject {
    func start(_ audio: AsyncStream<AudioChunk>) async throws -> AsyncStream<[TimedWord]>
    func stop() async
}

/// Splits recognised text into timed words. When a run of text carries one time range for
/// several words, the range is shared out evenly between them.
enum TranscriptBuilder {
    static func words(from text: String, start: Double, end: Double) -> [TimedWord] {
        let parts = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !parts.isEmpty else { return [] }
        let step = max(end - start, 0) / Double(parts.count)
        return parts.enumerated().map { index, part in
            TimedWord(text: part, start: start + Double(index) * step, end: start + Double(index + 1) * step)
        }
    }
}

/// Microphone capture for the prompter when it isn't recording.
@MainActor
final class MicrophoneStream {
    private let engine = AVAudioEngine()
    private var continuation: AsyncStream<AudioChunk>.Continuation?

    func start() throws -> AsyncStream<AudioChunk> {
        stop()
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw SpeechServiceError.audioInputUnavailable }

        let (stream, continuation) = AsyncStream.makeStream(of: AudioChunk.self, bufferingPolicy: .bufferingNewest(64))
        self.continuation = continuation
        Self.installTap(on: input, format: format, continuation: continuation)
        engine.prepare()
        try engine.start()
        return stream
    }

    func stop() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        continuation?.finish()
        continuation = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// `nonisolated` so the tap block isn't main-actor isolated: it runs on the audio thread.
    private nonisolated static func installTap(on node: AVAudioInputNode, format: AVAudioFormat, continuation: AsyncStream<AudioChunk>.Continuation) {
        node.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            continuation.yield(AudioChunk(buffer: buffer))
        }
    }
}

/// Converts audio to the format a recogniser wants.
final class AudioFormatConverter {
    private var converter: AVAudioConverter?
    private let output: AVAudioFormat

    init(output: AVAudioFormat) {
        self.output = output
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if buffer.format == output { return buffer }
        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: output)
            converter?.primeMethod = .none
        }
        guard let converter else { return nil }
        let ratio = output.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
        guard let converted = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else { return nil }
        let source = OneShotInput(buffer)
        var error: NSError?
        let status = converter.convert(to: converted, error: &error) { _, inputStatus in
            guard let next = source.take() else {
                inputStatus.pointee = .noDataNow
                return nil
            }
            inputStatus.pointee = .haveData
            return next
        }
        guard status != .error, error == nil else { return nil }
        return converted
    }
}

/// Hands a buffer to `AVAudioConverter` exactly once. The converter calls its input block
/// synchronously inside `convert`, so there is no real sharing across threads.
private final class OneShotInput: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func take() -> AVAudioPCMBuffer? {
        defer { buffer = nil }
        return buffer
    }
}
