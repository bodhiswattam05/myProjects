import CueCore
import SwiftData
import SwiftUI
import UIKit

/// Full-screen prompter for rehearsing or reading without recording.
struct PrompterScreen: View {
    @State private var model: PrompterViewModel
    @State private var showsSettings = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(script: Script, settings: PrompterSettings, speech: any SpeechRecognizing) {
        _model = State(initialValue: PrompterViewModel(title: script.displayTitle, text: script.body, settings: settings, speech: speech))
    }

    init(model: PrompterViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ZStack {
            PrompterStage(model: model)
                .ignoresSafeArea()

            PrompterChrome(model: model, showsSettings: $showsSettings, onClose: close) {
                EmptyView()
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(!model.controlsVisible)
        .persistentSystemOverlays(model.controlsVisible ? .automatic : .hidden)
        .prompterKeyCommands(model)
        .sheet(isPresented: $showsSettings) {
            PrompterSettingsSheet(settings: $model.settings)
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            model.teardown()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.pause() }
        }
    }

    private func close() {
        model.teardown()
        dismiss()
    }
}

/// Controls shared by the prompter and the recorder. Auto-hides two seconds after the
/// last interaction while the script is moving.
struct PrompterChrome<Accessory: View>: View {
    @Bindable var model: PrompterViewModel
    @Binding var showsSettings: Bool
    var onClose: () -> Void
    /// Extra controls in the bottom bar (the recorder puts its record button here).
    @ViewBuilder var accessory: () -> Accessory

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if case let .countdown(value) = model.phase {
                CountdownView(value: value)
            }
            if model.phase == .finished {
                FinishedBanner { model.restart(); model.start() }
            }
            VStack(spacing: CueSpacing.m) {
                if model.controlsVisible {
                    topBar
                        .transition(.opacity)
                }
                if case let .unavailable(message) = model.voiceStatus, model.settings.pacing == .voice {
                    VoiceNotice(message: message)
                        .transition(.opacity)
                }
                Spacer()
                if model.controlsVisible {
                    bottomBar
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, CueSpacing.l)
            .padding(.vertical, CueSpacing.s)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: model.controlsVisible)
        .sensoryFeedback(trigger: model.phase) { _, new in
            if case .countdown = new { return .impact(weight: .light) }
            if new == .running { return .impact(weight: .medium) }
            return nil
        }
    }

    private var topBar: some View {
        GlassEffectContainer {
            HStack(spacing: CueSpacing.m) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .accessibilityLabel(Text("Close prompter"))
                .accessibilityIdentifier("prompter.close")

                Text(model.title)
                    .font(.headline)
                    .foregroundStyle(CueColor.stageText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)

                PacingToggle(pacing: $model.settings.pacing)

                Button {
                    showsSettings = true
                } label: {
                    Image(systemName: "textformat.size")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .accessibilityLabel(Text("Display settings"))
                .accessibilityIdentifier("prompter.settings")
            }
        }
    }

    private var bottomBar: some View {
        GlassEffectContainer {
            HStack(spacing: CueSpacing.m) {
                Button { model.jumpToPreviousSection() } label: {
                    Image(systemName: "backward.end")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .accessibilityLabel(Text("Previous section"))

                if model.effectivePacing == .manual {
                    SpeedControl(speed: $model.settings.speed)
                }

                Button {
                    model.togglePlayPause()
                    model.noteInteraction()
                } label: {
                    Image(systemName: model.phase == .running ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .frame(width: 64, height: 64)
                }
                .buttonStyle(.glassProminent)
                .tint(CueColor.tungsten)
                .foregroundStyle(CueColor.ink)
                .accessibilityLabel(model.phase == .running ? Text("Pause") : Text("Play"))
                .accessibilityIdentifier("prompter.playPause")

                accessory()

                Button { model.jumpToNextSection() } label: {
                    Image(systemName: "forward.end")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .accessibilityLabel(Text("Next section"))
            }
        }
    }
}

private struct PacingToggle: View {
    @Binding var pacing: PrompterSettings.Pacing

    var body: some View {
        Button {
            pacing = pacing == .voice ? .manual : .voice
        } label: {
            Image(systemName: pacing == .voice ? "waveform" : "arrow.down")
                .symbolEffect(.variableColor.iterative, isActive: pacing == .voice)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.glass)
        .tint(pacing == .voice ? CueColor.tungsten : nil)
        .accessibilityLabel(Text("Follow my voice"))
        .accessibilityValue(pacing == .voice ? Text("On") : Text("Off"))
        .accessibilityIdentifier("prompter.pacing")
    }
}

private struct SpeedControl: View {
    @Binding var speed: Double

    var body: some View {
        HStack(spacing: 0) {
            Button { change(-0.5) } label: {
                Image(systemName: "tortoise").frame(width: 40, height: 44)
            }
            .accessibilityLabel(Text("Slower"))
            Text(speed, format: .number.precision(.fractionLength(1)))
                .monospacedDigit()
                .font(.subheadline.weight(.semibold))
                .frame(minWidth: 34)
                .accessibilityHidden(true)
            Button { change(0.5) } label: {
                Image(systemName: "hare").frame(width: 40, height: 44)
            }
            .accessibilityLabel(Text("Faster"))
        }
        .foregroundStyle(CueColor.stageText)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Speed"))
        .accessibilityValue(Text(speed, format: .number.precision(.fractionLength(1))))
        .accessibilityAdjustableAction { direction in
            change(direction == .increment ? 0.5 : -0.5)
        }
    }

    private func change(_ delta: Double) {
        speed = min(max(speed + delta, PrompterSettings.speedRange.lowerBound), PrompterSettings.speedRange.upperBound)
    }
}

private struct CountdownView: View {
    let value: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(value, format: .number)
            .font(.system(size: 120, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(CueColor.tungsten)
            .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
            .animation(reduceMotion ? nil : .snappy, value: value)
            .padding(CueSpacing.xxl)
            .glassEffect(.regular, in: .circle)
            .accessibilityLabel(Text("Starting in \(value)"))
            .accessibilityIdentifier("prompter.countdown")
    }
}

private struct FinishedBanner: View {
    var onRestart: () -> Void

    var body: some View {
        VStack(spacing: CueSpacing.m) {
            Text("End of script")
                .font(.title3.weight(.semibold))
                .foregroundStyle(CueColor.stageText)
            Button("Start over", systemImage: "arrow.counterclockwise", action: onRestart)
                .buttonStyle(.glass)
        }
        .padding(CueSpacing.xl)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }
}

private struct VoiceNotice: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "waveform.slash")
            .font(.footnote)
            .foregroundStyle(CueColor.stageText)
            .padding(.horizontal, CueSpacing.l)
            .padding(.vertical, CueSpacing.m)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
            .accessibilityIdentifier("prompter.voiceNotice")
    }
}

extension View {
    /// Space plays or pauses; arrows and Page Up/Down (what most presentation clickers send)
    /// move between sections or change speed. Works with any Bluetooth keyboard.
    func prompterKeyCommands(_ model: PrompterViewModel) -> some View {
        modifier(PrompterKeyCommands(model: model))
    }
}

private struct PrompterKeyCommands: ViewModifier {
    let model: PrompterViewModel
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .onAppear { focused = true }
            .onKeyPress(keys: [.space, .return, .rightArrow, .pageDown, .leftArrow, .pageUp, .upArrow, .downArrow]) { press in
                switch press.key {
                case .space, .return:
                    model.togglePlayPause()
                case .rightArrow, .pageDown:
                    model.jumpToNextSection()
                case .leftArrow, .pageUp:
                    model.jumpToPreviousSection()
                case .upArrow:
                    model.settings.speed = min(model.settings.speed + 0.5, PrompterSettings.speedRange.upperBound)
                case .downArrow:
                    model.settings.speed = max(model.settings.speed - 0.5, PrompterSettings.speedRange.lowerBound)
                default:
                    return .ignored
                }
                model.noteInteraction()
                return .handled
            }
    }
}

#Preview("Prompter") {
    let model = PrompterViewModel(title: "Welcome to Cue", text: SampleData.scripts[0].body, settings: PrompterSettings(), speech: AppServices.preview.speech)
    PrompterScreen(model: model)
        .previewEnvironment()
}
