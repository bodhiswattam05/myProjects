import AVFoundation
import Observation
import Photos
import Speech
import UIKit

/// Tracks and requests the permissions Cue uses. Every request is made only after the
/// app has explained, in one line, why it's needed.
@MainActor
@Observable
final class PermissionCenter {
    enum Kind: String, CaseIterable, Identifiable {
        case microphone
        case camera
        case speech

        var id: String { rawValue }

        var title: String {
            switch self {
            case .microphone: String(localized: "Microphone")
            case .camera: String(localized: "Camera")
            case .speech: String(localized: "Speech recognition")
            }
        }

        var reason: String {
            switch self {
            case .microphone: String(localized: "So the script can follow your voice, and takes have sound.")
            case .camera: String(localized: "So you can record takes with the script on screen.")
            case .speech: String(localized: "So Cue can match your words to the script, on this device.")
            }
        }

        var systemImage: String {
            switch self {
            case .microphone: "mic"
            case .camera: "camera"
            case .speech: "waveform"
            }
        }
    }

    enum Status: Equatable {
        case notDetermined
        case granted
        case denied
    }

    private(set) var statuses: [Kind: Status] = [:]

    init() {
        refresh()
    }

    func status(_ kind: Kind) -> Status {
        statuses[kind] ?? .notDetermined
    }

    func refresh() {
        statuses[.microphone] = Self.microphoneStatus()
        statuses[.camera] = Self.cameraStatus()
        statuses[.speech] = Self.speechStatus()
    }

    func request(_ kind: Kind) async {
        switch kind {
        case .microphone:
            _ = await AVAudioApplication.requestRecordPermission()
        case .camera:
            _ = await AVCaptureDevice.requestAccess(for: .video)
        case .speech:
            _ = await Self.requestSpeechAuthorization()
        }
        refresh()
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    static func microphoneAndSpeechGranted() async -> Bool {
        // SpeechAnalyzer itself only needs the microphone; the fallback also needs speech access.
        microphoneStatus() == .granted
    }

    static func microphoneStatus() -> Status {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: .granted
        case .denied: .denied
        default: .notDetermined
        }
    }

    static func cameraStatus() -> Status {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .granted
        case .denied, .restricted: .denied
        default: .notDetermined
        }
    }

    static func speechStatus() -> Status {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: .granted
        case .denied, .restricted: .denied
        default: .notDetermined
        }
    }

    /// `nonisolated` because the callback arrives on an arbitrary queue.
    nonisolated static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    /// Asks for add-only Photos access, used when exporting a take.
    nonisolated static func requestPhotosAddAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        return status == .authorized || status == .limited
    }
}
