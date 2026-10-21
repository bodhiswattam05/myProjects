import CueCore
import Observation
import SwiftUI

/// Drives the stage: scroll position, countdown, steady or voice pacing, section jumps
/// and scrubbing. Layout is reported back by the view (`setLineFrame`), so the model
/// knows where every line sits.
///
/// Coordinates: line frames are in content space, starting at 0 for the first line.
/// `offset` is the content y that sits at the top of the reading band.
@MainActor
@Observable
final class PrompterViewModel {
    enum Phase: Equatable {
        case ready
        case countdown(Int)
        case running
        case paused
        case finished

        /// Counting down or scrolling.
        var isActive: Bool {
            switch self {
            case .countdown, .running: true
            case .ready, .paused, .finished: false
            }
        }
    }

    enum VoiceStatus: Equatable {
        case off
        case starting
        case listening
        /// Voice pacing couldn't start; the prompter scrolls steadily instead.
        case unavailable(String)
    }

    let document: ScriptDocument
    let title: String
    var settings: PrompterSettings {
        didSet { if oldValue.pacing != settings.pacing { pacingChanged() } }
    }

    private(set) var phase: Phase = .ready
    private(set) var offset: Double = 0
    /// Voice pacing: index of the last word spoken, or -1.
    private(set) var spokenThrough = -1
    private(set) var voiceStatus: VoiceStatus = .off
    /// Everything recognised during this session, with timings (for the delivery coach).
    private(set) var transcript: [TimedWord] = []
    var controlsVisible = true
    /// Increments on each section jump, so the view can play a haptic.
    private(set) var sectionJumpCount = 0

    @ObservationIgnored private var lineFrames: [Int: CGRect] = [:]
    @ObservationIgnored private(set) var stageHeight: Double = 0
    @ObservationIgnored private var spring = ScrollSpring()
    @ObservationIgnored private var aligner: TranscriptAligner
    @ObservationIgnored private let speech: (any SpeechRecognizing)?
    @ObservationIgnored private let displayLink = DisplayLinkDriver()
    @ObservationIgnored private var lastFrameTime: CFTimeInterval?
    @ObservationIgnored private var jumpTarget: Double?
    @ObservationIgnored private var scrubStartOffset: Double?
    @ObservationIgnored private var listenTask: Task<Void, Never>?
    @ObservationIgnored private var countdownTask: Task<Void, Never>?
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    /// True when the transcript comes from outside (a recording), not our own microphone.
    @ObservationIgnored private var usesExternalTranscript = false

    init(title: String, text: String, settings: PrompterSettings, speech: (any SpeechRecognizing)?) {
        self.title = title
        self.document = ScriptParser.parse(text)
        self.settings = settings
        self.speech = speech
        self.aligner = TranscriptAligner(document: document)
        speech?.prepare(for: document)
    }

    // MARK: Derived state

    /// Pacing actually in effect: voice falls back to steady when it can't start.
    var effectivePacing: PrompterSettings.Pacing {
        if settings.pacing == .voice, case .unavailable = voiceStatus { return .manual }
        return settings.pacing
    }

    var lineHeight: Double {
        settings.fontSize * (1.2 + settings.typeface.extraLeading)
    }

    var readingLineY: Double { stageHeight * settings.readingLinePosition }

    var maxOffset: Double {
        lineFrames.values.map(\.minY).max() ?? 0
    }

    /// The line whose text sits in the reading band.
    var currentLineID: Int? {
        let probe = offset + lineHeight * 0.5
        let sorted = lineFrames.sorted { $0.value.minY < $1.value.minY }
        return sorted.last { $0.value.minY <= probe }?.key ?? sorted.first?.key
    }

    /// In steady mode a line counts as read once it has scrolled above the band.
    func isLineRead(_ lineID: Int) -> Bool {
        guard let frame = lineFrames[lineID] else { return false }
        return frame.maxY <= offset + 1
    }

    var progress: Double {
        guard maxOffset > 0 else { return 0 }
        return min(1, max(0, offset / maxOffset))
    }

    // MARK: Layout

    func setStageHeight(_ height: Double) {
        stageHeight = height
    }

    func setLineFrame(_ lineID: Int, frame: CGRect) {
        lineFrames[lineID] = frame
    }

    // MARK: Transport

    func togglePlayPause() {
        switch phase {
        case .ready, .finished: start()
        case .countdown: cancelCountdown()
        case .running: pause()
        case .paused: resume()
        }
    }

    func start() {
        if phase == .finished { restart() }
        countdownTask?.cancel()
        let seconds = settings.countdownSeconds
        guard seconds > 0 else { beginRunning(); return }
        phase = .countdown(seconds)
        countdownTask = Task { [weak self] in
            for remaining in stride(from: seconds, through: 1, by: -1) {
                self?.phase = .countdown(remaining)
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            self?.beginRunning()
        }
    }

    func pause() {
        guard phase == .running else { return }
        phase = .paused
        displayLink.stop()
        lastFrameTime = nil
        if !usesExternalTranscript { stopListening() }
        controlsVisible = true
        hideTask?.cancel()
    }

    func resume() {
        guard phase == .paused else { return }
        beginRunning()
    }

    func restart() {
        offset = 0
        spring.jump(to: 0)
        spokenThrough = -1
        aligner.reset(to: -1)
        jumpTarget = nil
        phase = .ready
    }

    /// Stops everything. Call when the prompter is dismissed.
    func teardown() {
        countdownTask?.cancel()
        hideTask?.cancel()
        displayLink.stop()
        stopListening()
    }

    private func cancelCountdown() {
        countdownTask?.cancel()
        phase = .ready
    }

    private func beginRunning() {
        phase = .running
        lastFrameTime = nil
        spring.jump(to: offset)
        if effectivePacing == .voice, !usesExternalTranscript, listenTask == nil {
            startListening()
        }
        displayLink.start { [weak self] time in self?.frame(at: time) }
        scheduleControlsHide()
    }

    // MARK: Frames

    private func frame(at time: CFTimeInterval) {
        defer { lastFrameTime = time }
        guard let last = lastFrameTime else { return }
        let deltaTime = min(max(time - last, 0), 0.1)
        guard phase == .running else { return }

        if let target = jumpTarget {
            var jump = ScrollSpring(position: offset, response: 0.45, maximumSpeed: 4000, allowsReverse: true)
            jump.velocity = spring.velocity
            offset = jump.step(toward: target, deltaTime: deltaTime)
            spring = ScrollSpring(position: offset, allowsReverse: false)
            spring.velocity = jump.velocity
            if abs(offset - target) < 0.5 {
                offset = target
                jumpTarget = nil
                spring.jump(to: offset)
            }
            return
        }

        switch effectivePacing {
        case .manual:
            offset = min(offset + settings.pointsPerSecond * deltaTime, maxOffset)
            if offset >= maxOffset, maxOffset > 0 { finish() }
        case .voice:
            offset = spring.step(toward: voiceTargetOffset(), deltaTime: deltaTime)
            if spokenThrough >= document.words.count - 1, !document.words.isEmpty, abs(offset - voiceTargetOffset()) < 1 {
                finish()
            }
        }
    }

    private func finish() {
        phase = .finished
        displayLink.stop()
        if !usesExternalTranscript { stopListening() }
        controlsVisible = true
    }

    /// Puts the line holding the next unread word at the reading line.
    private func voiceTargetOffset() -> Double {
        let next = min(spokenThrough + 1, document.words.count - 1)
        guard next >= 0, let frame = lineFrames[document.words[next].lineID] else { return offset }
        return frame.minY
    }

    // MARK: Sections and scrubbing

    func jumpToNextSection() {
        let fromWord = currentWordIndex()
        guard let next = document.firstWordOfNextSection(after: fromWord) else { return }
        jump(toWord: next)
    }

    func jumpToPreviousSection() {
        let fromWord = currentWordIndex()
        guard let section = document.sectionIndex(forWord: fromWord) else { return }
        let sectionStart = document.sections[section].wordRange?.lowerBound ?? 0
        // Already at the top of a section: go to the one before.
        let target: Int
        if fromWord <= sectionStart, section > 0 {
            target = document.sections[section - 1].wordRange?.lowerBound ?? 0
        } else {
            target = sectionStart
        }
        jump(toWord: target)
    }

    private func jump(toWord index: Int) {
        guard document.words.indices.contains(index), let frame = lineFrames[document.words[index].lineID] else { return }
        spokenThrough = index - 1
        aligner.reset(to: index - 1)
        if let simulated = speech as? SimulatedSpeechService, effectivePacing == .voice, !usesExternalTranscript {
            simulated.skip(toScriptWord: index)
            restartListening()
        }
        sectionJumpCount += 1
        if phase == .running {
            jumpTarget = frame.minY
        } else {
            offset = frame.minY
            spring.jump(to: offset)
            if phase == .finished { phase = .paused }
        }
        noteInteraction()
    }

    func beginScrub() {
        scrubStartOffset = offset
        jumpTarget = nil
        noteInteraction()
    }

    func scrub(by translation: Double) {
        guard let start = scrubStartOffset else { return }
        offset = min(max(start - translation, 0), maxOffset)
        spring.jump(to: offset)
    }

    func endScrub() {
        scrubStartOffset = nil
        // Voice pacing continues from the line now at the reading band.
        let index = currentWordIndex()
        spokenThrough = index - 1
        aligner.reset(to: index - 1)
        if phase == .finished { phase = .paused }
        noteInteraction()
    }

    /// First word of the line in the reading band (steady), or the next unread word (voice).
    private func currentWordIndex() -> Int {
        if effectivePacing == .voice, phase == .running || phase == .paused {
            return max(0, min(spokenThrough + 1, document.words.count - 1))
        }
        guard let lineID = currentLineID else { return 0 }
        return document.words.firstIndex { $0.lineID == lineID } ?? document.words.lastIndex { $0.lineID < lineID } ?? 0
    }

    // MARK: Voice

    private func pacingChanged() {
        if settings.pacing == .manual {
            stopListening()
            voiceStatus = .off
        } else if phase == .running, !usesExternalTranscript {
            startListening()
        }
    }

    /// Follows a transcript supplied by someone else (the recorder's microphone stream).
    func follow(transcript stream: AsyncStream<[TimedWord]>) {
        usesExternalTranscript = true
        listenTask?.cancel()
        voiceStatus = .listening
        listenTask = Task { [weak self] in
            for await words in stream {
                self?.handle(words)
            }
        }
    }

    /// Marks voice pacing unavailable (for example the recorder couldn't start speech).
    func voiceUnavailable(_ message: String) {
        voiceStatus = .unavailable(message)
    }

    func stopFollowingExternalTranscript() {
        usesExternalTranscript = false
        listenTask?.cancel()
        listenTask = nil
    }

    private func startListening() {
        guard let speech else {
            voiceStatus = .unavailable(SpeechAvailability.unavailable.message)
            return
        }
        listenTask?.cancel()
        voiceStatus = .starting
        listenTask = Task { [weak self] in
            let availability = await speech.availability()
            guard let self, !Task.isCancelled else { return }
            guard availability.isReady else {
                self.voiceStatus = .unavailable(availability.message)
                self.listenTask = nil
                return
            }
            do {
                let stream = try await speech.startListening()
                self.voiceStatus = .listening
                for await words in stream {
                    self.handle(words)
                }
            } catch {
                self.voiceStatus = .unavailable(error.localizedDescription)
            }
            self.listenTask = nil
        }
    }

    private func restartListening() {
        stopListening()
        if phase == .running { startListening() }
    }

    private func stopListening() {
        listenTask?.cancel()
        listenTask = nil
        if let speech, !usesExternalTranscript {
            Task { await speech.stop() }
        }
        if case .listening = voiceStatus { voiceStatus = .off }
        if voiceStatus == .starting { voiceStatus = .off }
    }

    /// Feeds a transcript snapshot to the aligner. Public for the Debug screen and tests.
    func handle(_ words: [TimedWord]) {
        transcript = words
        guard effectivePacing == .voice else { return }
        let normalized = words.map { Normalizer.normalize($0.text) }
        let update = aligner.update(transcript: normalized)
        if update.position != spokenThrough {
            spokenThrough = update.position
        }
    }

    // MARK: Controls visibility

    func noteInteraction() {
        controlsVisible = true
        scheduleControlsHide()
    }

    private func scheduleControlsHide() {
        hideTask?.cancel()
        guard phase.isActive else { return }
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self, self.phase == .running else { return }
            self.controlsVisible = false
        }
    }
}
