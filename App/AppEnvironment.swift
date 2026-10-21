import CueCore
import SwiftUI

/// The app's hardware- and framework-dependent services, injected through the SwiftUI
/// environment (`@Environment(AppServices.self)`) so previews and tests can swap in
/// simulated versions.
@MainActor
@Observable
final class AppServices {
    let camera: any CameraControlling
    let speech: any SpeechRecognizing
    /// Present whenever `speech` is simulated, so the Debug screen can script it.
    let simulatedSpeech: SimulatedSpeechService?
    let permissions: PermissionCenter

    init(camera: any CameraControlling, speech: any SpeechRecognizing, simulatedSpeech: SimulatedSpeechService? = nil, permissions: PermissionCenter) {
        self.camera = camera
        self.speech = speech
        self.simulatedSpeech = simulatedSpeech
        self.permissions = permissions
    }

    /// Real camera and speech on devices; simulated camera in the Simulator.
    static func live() -> AppServices {
        #if targetEnvironment(simulator)
        let camera: any CameraControlling = SimulatedCameraService()
        #else
        let camera: any CameraControlling = LiveCameraService()
        #endif
        return AppServices(camera: camera, speech: LiveSpeechService(), permissions: PermissionCenter())
    }

    /// Everything simulated: previews, UI tests, and the Debug fake-transcript player.
    static func simulated() -> AppServices {
        let speech = SimulatedSpeechService()
        return AppServices(camera: SimulatedCameraService(), speech: speech, simulatedSpeech: speech, permissions: PermissionCenter())
    }
}

/// How the app was launched. UI tests pass `-ui-testing` to get a clean, simulated app.
enum LaunchMode {
    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-testing")
    }

    static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil && !isUITesting
    }
}

extension AppServices {
    /// Shared simulated services for SwiftUI previews.
    static let preview = AppServices.simulated()
}

extension View {
    /// Injects simulated services and an in-memory store with sample data, for previews.
    func previewEnvironment() -> some View {
        environment(AppServices.preview)
            .modelContainer(ModelContainerFactory.preview())
    }
}

/// User preferences that aren't stored in SwiftData.
enum PreferenceKey {
    static let hasCompletedOnboarding = "cue.hasCompletedOnboarding"
    static let defaultWordsPerMinute = "cue.defaultWordsPerMinute"
    static let lastPresetID = "cue.lastPresetID"
}

enum UserPreferences {
    /// Pace used for new scripts and read-time estimates, from Settings.
    static var defaultWordsPerMinute: Int {
        let stored = UserDefaults.standard.integer(forKey: PreferenceKey.defaultWordsPerMinute)
        return stored == 0 ? ReadTimeEstimator.defaultWordsPerMinute : stored
    }
}
