import CueCore
import SwiftData
import SwiftUI

/// Developer tools, reachable from Settings in debug builds.
struct DebugView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Script.editedAt, order: .reverse)]) private var scripts: [Script]
    @AppStorage(PreferenceKey.hasCompletedOnboarding) private var hasCompletedOnboarding = true

    @State private var selectedScriptID: UUID?
    @State private var wordsPerMinute = 150.0
    @State private var messiness = 0.5
    @State private var simulation: SimulationSession?
    @State private var didReset = false

    var body: some View {
        Form {
            Section {
                Picker("Script", selection: $selectedScriptID) {
                    ForEach(scripts) { script in
                        Text(script.displayTitle).tag(Optional(script.id))
                    }
                }
                LabeledSlider(title: "Speaking pace", value: $wordsPerMinute, range: 80...220, step: 10) {
                    Text("\(Int(wordsPerMinute)) wpm")
                }
                LabeledSlider(title: "Messiness", value: $messiness, range: 0...1, step: 0.1) {
                    Text(messiness, format: .percent.precision(.fractionLength(0)))
                }
                Button("Play fake transcript", systemImage: "waveform") { startSimulation() }
                    .disabled(selectedScript == nil)
                    .accessibilityIdentifier("debug.playFakeTranscript")
            } header: {
                Text("Voice pacing simulator")
            } footer: {
                Text("Plays a made-up reading of the script, with skipped words, ad-libs, fillers and long pauses in proportion to messiness. The prompter follows it exactly as it would follow your voice.")
            }

            Section {
                Button("Reset sample data", systemImage: "arrow.counterclockwise") {
                    SampleData.reset(modelContext)
                    didReset = true
                }
                .accessibilityIdentifier("debug.resetSamples")
                if didReset {
                    Text("Sample scripts and built-in presets restored.")
                        .foregroundStyle(CueColor.secondaryText)
                }
                Button("Show onboarding next launch", systemImage: "hand.wave") {
                    hasCompletedOnboarding = false
                }
            } header: {
                Text("Data")
            }
        }
        .navigationTitle("Debug tools")
        .onAppear {
            if selectedScriptID == nil { selectedScriptID = scripts.first?.id }
        }
        .fullScreenCover(item: $simulation) { session in
            PrompterScreen(model: session.model)
        }
    }

    private var selectedScript: Script? {
        scripts.first { $0.id == selectedScriptID }
    }

    private func startSimulation() {
        guard let script = selectedScript else { return }
        var options = TranscriptSimulator.Options()
        options.wordsPerMinute = wordsPerMinute
        options.skipRate = 0.08 * messiness
        options.adLibRate = 0.08 * messiness
        options.mispronounceRate = 0.15 * messiness
        options.fillerRate = 0.06 * messiness
        options.longPauseRate = 0.03 * messiness
        options.seed = UInt64.random(in: 1...10_000)

        let speech = SimulatedSpeechService()
        speech.configure(document: ScriptParser.parse(script.body), options: options)
        var settings = PrompterSettings()
        settings.pacing = .voice
        let model = PrompterViewModel(title: script.displayTitle, text: script.body, settings: settings, speech: speech)
        simulation = SimulationSession(model: model)
    }
}

struct SimulationSession: Identifiable {
    let id = UUID()
    let model: PrompterViewModel
}

#Preview("Debug") {
    NavigationStack {
        DebugView()
    }
    .previewEnvironment()
}
