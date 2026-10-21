import CueCore
import Observation
import SwiftData
import SwiftUI

/// Runs a recording session: camera preview, the prompter on top, speech from the take's
/// own audio (so one microphone stream feeds both the movie and voice pacing), and the
/// delivery coach when the take ends.
@MainActor
@Observable
final class RecordingViewModel {
    enum State: Equatable {
        case preparing
        case ready
        case recording(startedAt: Date)
        case saving
        case failed(String)

        var isRecording: Bool { if case .recording = self { true } else { false } }
    }

    let prompter: PrompterViewModel
    let camera: any CameraControlling
    private(set) var state: State = .preparing
    /// The take just saved, to show its coach card.
    var finishedTake: Take?

    @ObservationIgnored private let speech: any SpeechRecognizing
    @ObservationIgnored private let permissions: PermissionCenter
    @ObservationIgnored private let script: Script
    @ObservationIgnored private let modelContext: ModelContext

    init(script: Script, settings: PrompterSettings, services: AppServices, modelContext: ModelContext) {
        self.script = script
        self.camera = services.camera
        self.speech = services.speech
        self.permissions = services.permissions
        self.modelContext = modelContext
        // The prompter doesn't open its own microphone here; it follows the recording's audio.
        prompter = PrompterViewModel(title: script.displayTitle, text: script.body, settings: settings, speech: services.speech)
    }

    // MARK: Camera

    func prepare() async {
        state = .preparing
        if !camera.isSimulated {
            if PermissionCenter.cameraStatus() == .notDetermined { await permissions.request(.camera) }
            if PermissionCenter.microphoneStatus() == .notDetermined { await permissions.request(.microphone) }
        }
        do {
            try await camera.configure(position: camera.position, resolution: camera.resolution, frameRate: camera.frameRate)
            camera.startPreview()
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func switchCamera() async {
        guard !state.isRecording else { return }
        let next: CameraPosition = camera.position == .front ? .back : .front
        await reconfigure(position: next, resolution: camera.resolution, frameRate: camera.frameRate)
    }

    func setResolution(_ resolution: VideoResolution) async {
        await reconfigure(position: camera.position, resolution: resolution, frameRate: camera.frameRate)
    }

    func setFrameRate(_ frameRate: Int) async {
        await reconfigure(position: camera.position, resolution: camera.resolution, frameRate: frameRate)
    }

    private func reconfigure(position: CameraPosition, resolution: VideoResolution, frameRate: Int) async {
        guard !state.isRecording else { return }
        do {
            try await camera.configure(position: position, resolution: resolution, frameRate: frameRate)
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: Recording

    func toggleRecording() async {
        if state.isRecording {
            await stopRecording()
        } else if state == .ready {
            await startRecording()
        }
    }

    func startRecording() async {
        do {
            let audio = try await camera.startRecording()
            state = .recording(startedAt: .now)
            await startVoicePacing(audio: audio)
            prompter.restart()
            prompter.start()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func startVoicePacing(audio: AsyncStream<AudioChunk>) async {
        // Listen whenever possible: the coach needs the transcript even with steady scrolling.
        let availability = await speech.availability()
        guard availability.isReady else {
            if prompter.settings.pacing == .voice { prompter.voiceUnavailable(availability.message) }
            return
        }
        do {
            let transcript = try await speech.startTranscribing(audio)
            prompter.follow(transcript: transcript)
        } catch {
            if prompter.settings.pacing == .voice { prompter.voiceUnavailable(error.localizedDescription) }
        }
    }

    func stopRecording() async {
        guard state.isRecording else { return }
        state = .saving
        prompter.pause()
        do {
            let result = try await camera.stopRecording()
            await speech.stop()
            prompter.stopFollowingExternalTranscript()
            saveTake(result)
            state = .ready
        } catch {
            await speech.stop()
            prompter.stopFollowingExternalTranscript()
            state = .failed(error.localizedDescription)
        }
    }

    private func saveTake(_ result: RecordingResult) {
        let take = Take(
            scriptTitle: script.displayTitle,
            script: script,
            duration: result.duration,
            fileName: result.url.lastPathComponent,
            cameraPosition: camera.position,
            resolutionLabel: "\(camera.resolution.label) · \(camera.frameRate) fps",
            isSimulated: camera.isSimulated
        )
        let transcript = prompter.transcript
        if !transcript.isEmpty {
            take.report = DeliveryCoach.analyze(
                transcript: transcript,
                document: prompter.document,
                targetWordsPerMinute: script.wordsPerMinute,
                duration: result.duration
            )
        }
        modelContext.insert(take)
        try? modelContext.save()
        finishedTake = take
    }

    func teardown() async {
        if state.isRecording { await stopRecording() }
        prompter.teardown()
        await speech.stop()
        camera.stopPreview()
    }
}
