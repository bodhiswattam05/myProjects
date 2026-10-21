import SwiftData
import SwiftUI

/// Display controls for the stage, plus saving and applying presets.
struct PrompterSettingsSheet: View {
    @Binding var settings: PrompterSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\PrompterPreset.createdAt)]) private var presets: [PrompterPreset]
    @State private var newPresetName = ""
    @State private var isNamingPreset = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(presets) { preset in
                        Button {
                            settings = preset.settings
                            UserDefaults.standard.set(preset.id.uuidString, forKey: PreferenceKey.lastPresetID)
                        } label: {
                            HStack {
                                Text(preset.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if preset.settings == settings {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(CueColor.accent)
                                        .accessibilityLabel(Text("Current"))
                                }
                            }
                        }
                        .swipeActions {
                            if !preset.isBuiltIn {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    modelContext.delete(preset)
                                }
                            }
                        }
                    }
                    Button("Save as preset", systemImage: "plus") {
                        newPresetName = ""
                        isNamingPreset = true
                    }
                } header: {
                    Text("Presets")
                }

                Section("Text") {
                    Picker("Typeface", selection: $settings.typeface) {
                        ForEach(PrompterTypeface.allCases) { Text($0.displayName).tag($0) }
                    }
                    LabeledSlider(title: "Size", value: $settings.fontSize, range: PrompterSettings.fontSizeRange, step: 2) {
                        Text("\(Int(settings.fontSize)) pt")
                    }
                    LabeledSlider(title: "Line spacing", value: $settings.lineSpacing, range: PrompterSettings.lineSpacingRange, step: 0.05) {
                        Text(settings.lineSpacing, format: .percent.precision(.fractionLength(0)))
                    }
                    LabeledSlider(title: "Margins", value: $settings.margin, range: PrompterSettings.marginRange, step: 0.01) {
                        Text(settings.margin, format: .percent.precision(.fractionLength(0)))
                    }
                    Picker("Alignment", selection: $settings.alignment) {
                        ForEach(PrompterSettings.Alignment.allCases) { Text($0.displayName).tag($0) }
                    }
                }

                Section {
                    Picker("Pacing", selection: $settings.pacing) {
                        ForEach(PrompterSettings.Pacing.allCases) { Text($0.displayName).tag($0) }
                    }
                    LabeledSlider(title: "Steady speed", value: $settings.speed, range: PrompterSettings.speedRange, step: 0.5) {
                        Text(settings.speed, format: .number.precision(.fractionLength(1)))
                    }
                    LabeledSlider(title: "Reading line", value: $settings.readingLinePosition, range: PrompterSettings.readingLineRange, step: 0.01) {
                        Text(settings.readingLinePosition, format: .percent.precision(.fractionLength(0)))
                    }
                    Stepper(value: $settings.countdownSeconds, in: 0...10) {
                        LabeledContent("Countdown", value: settings.countdownSeconds == 0 ? String(localized: "Off") : String(localized: "\(settings.countdownSeconds) sec"))
                    }
                    Toggle("Mirror text", isOn: $settings.isMirrored)
                } header: {
                    Text("Movement")
                } footer: {
                    Text("Mirror flips the text for beam-splitter glass. Follow my voice listens on this device only.")
                }
            }
            .navigationTitle("Display")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Name this preset", isPresented: $isNamingPreset) {
                TextField("Preset name", text: $newPresetName)
                Button("Save") { savePreset() }
                Button("Cancel", role: .cancel) {}
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.regularMaterial)
    }

    private func savePreset() {
        let name = newPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
        let preset = PrompterPreset(name: name.isEmpty ? String(localized: "My preset") : name, settings: settings)
        modelContext.insert(preset)
        try? modelContext.save()
    }
}

struct LabeledSlider<Value: View>: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    @ViewBuilder var valueLabel: () -> Value

    var body: some View {
        VStack(alignment: .leading, spacing: CueSpacing.xs) {
            HStack {
                Text(title)
                Spacer()
                valueLabel()
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range, step: step) {
                Text(title)
            }
        }
    }
}

#Preview("Display settings") {
    @Previewable @State var settings = PrompterSettings()
    PrompterSettingsSheet(settings: $settings)
        .previewEnvironment()
}
