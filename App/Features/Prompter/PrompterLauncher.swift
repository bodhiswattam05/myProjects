import SwiftData
import SwiftUI

/// Opens the prompter for a script with the most recently used preset.
struct PrompterLauncher: View {
    let script: Script
    @Environment(AppServices.self) private var services
    @Query private var presets: [PrompterPreset]

    var body: some View {
        PrompterScreen(script: script, settings: LastUsedSettings.resolve(presets), speech: services.speech)
    }
}

/// The settings the prompter opens with: the last preset the user applied, or defaults.
enum LastUsedSettings {
    static func resolve(_ presets: [PrompterPreset]) -> PrompterSettings {
        let id = UserDefaults.standard.string(forKey: PreferenceKey.lastPresetID)
        return presets.first { $0.id.uuidString == id }?.settings ?? PrompterSettings()
    }
}
