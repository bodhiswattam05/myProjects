import CueCore
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services
    @AppStorage(PreferenceKey.defaultWordsPerMinute) private var defaultWordsPerMinute = ReadTimeEstimator.defaultWordsPerMinute
    @AppStorage(ModelContainerFactory.cloudSyncKey) private var iCloudSync = false
    @State private var speechAvailability: SpeechAvailability?
    @State private var isInstallingModel = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PrivacyStatement()
                        .padding(.vertical, CueSpacing.xs)
                } header: {
                    Text("Privacy")
                }

                Section {
                    Stepper(value: $defaultWordsPerMinute, in: ReadTimeEstimator.wordsPerMinuteRange, step: 10) {
                        LabeledContent("Pace for new scripts", value: String(localized: "\(defaultWordsPerMinute) wpm"))
                    }
                } header: {
                    Text("Reading")
                } footer: {
                    Text("Used for read-time estimates. Each script can have its own pace.")
                }

                Section {
                    LabeledContent("Status", value: speechStatusText)
                    if speechAvailability == .needsModel {
                        Button(isInstallingModel ? "Downloading…" : "Download speech model") {
                            Task { await installModel() }
                        }
                        .disabled(isInstallingModel)
                    }
                } header: {
                    Text("Follow my voice")
                } footer: {
                    Text("Speech is recognised on this device. It works in airplane mode once the model is installed.")
                }

                Section("Permissions") {
                    ForEach(PermissionCenter.Kind.allCases) { kind in
                        PermissionRow(kind: kind, permissions: services.permissions)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }

                Section {
                    Toggle("Sync with iCloud", isOn: $iCloudSync)
                        .disabled(!ModelContainerFactory.isCloudSyncAvailable)
                } header: {
                    Text("iCloud")
                } footer: {
                    if ModelContainerFactory.isCloudSyncAvailable {
                        Text("Off by default. When on, scripts, folders and presets sync through your private iCloud database. Takes never sync. Takes effect the next time you open Cue.")
                    } else {
                        Text("iCloud sync isn't set up in this build. It's the only feature that would use the network, and only if you turn it on.")
                    }
                }

                #if DEBUG
                Section("Developer") {
                    NavigationLink("Debug tools") { DebugView() }
                        .accessibilityIdentifier("settings.debug")
                }
                #endif

                Section {
                    LabeledContent("Version", value: Bundle.main.versionString)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("settings.done")
                }
            }
            .task {
                services.permissions.refresh()
                speechAvailability = await services.speech.availability()
            }
        }
    }

    private var speechStatusText: String {
        switch speechAvailability {
        case nil: String(localized: "Checking…")
        case .ready: String(localized: "Ready, works offline")
        case .needsModel: String(localized: "Needs a one-time download")
        case .notAuthorized: String(localized: "Needs microphone access")
        case .unsupportedLanguage: String(localized: "Not available in your language")
        case .unavailable: String(localized: "Not available on this device")
        }
    }

    private func installModel() async {
        isInstallingModel = true
        defer { isInstallingModel = false }
        try? await services.speech.installModel()
        speechAvailability = await services.speech.availability()
    }
}

extension Bundle {
    var versionString: String {
        let version = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }
}

#Preview("Settings") {
    SettingsView()
        .previewEnvironment()
}
