import SwiftData
import SwiftUI
import UIKit

/// Opens the recorder for a script with the last-used preset.
struct RecorderLauncher: View {
    let script: Script
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Query private var presets: [PrompterPreset]

    var body: some View {
        RecordingScreen(
            model: RecordingViewModel(
                script: script,
                settings: LastUsedSettings.resolve(presets),
                services: services,
                modelContext: modelContext
            )
        )
    }
}

/// Camera preview with the script overlaid near the lens. The overlay is SwiftUI on top of
/// the preview, so it's never in the recorded video.
struct RecordingScreen: View {
    @State private var model: RecordingViewModel
    @State private var showsSettings = false
    @State private var interfaceOrientation: UIInterfaceOrientation = .portrait
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    init(model: RecordingViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        GeometryReader { geometry in
            let placement = LensPlacement.make(
                size: geometry.size,
                orientation: interfaceOrientation,
                isPad: UIDevice.current.userInterfaceIdiom == .pad,
                camera: model.camera.position
            )
            ZStack {
                CameraPreview(view: model.camera.previewView)
                    .ignoresSafeArea()

                PrompterStage(
                    model: model.prompter,
                    showsBackground: false,
                    columnWidthFraction: placement.widthFraction,
                    columnAlignment: placement.alignment
                )
                .background(alignment: placement.alignment) {
                    CueColor.stage.opacity(0.82)
                        .frame(width: geometry.size.width * placement.widthFraction)
                }
                .frame(height: geometry.size.height * placement.heightFraction)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(edges: .top)

                PrompterChrome(model: model.prompter, showsSettings: $showsSettings, onClose: close) {
                    RecordButton(isRecording: model.state.isRecording, isBusy: model.state == .saving || model.state == .preparing) {
                        Task { await model.toggleRecording() }
                    }
                    CameraMenu(model: model)
                }

                if model.state.isRecording, case let .recording(startedAt) = model.state {
                    RecordingIndicator(startedAt: startedAt)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 110)
                }

                if case let .failed(message) = model.state {
                    CameraProblem(message: message) { Task { await model.prepare() } }
                }
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { _ in
                interfaceOrientation = Self.currentOrientation()
                model.camera.updateRotation()
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .prompterKeyCommands(model.prompter)
        .sensoryFeedback(trigger: model.state.isRecording) { _, recording in
            recording ? .start : .stop
        }
        .sheet(isPresented: $showsSettings) {
            PrompterSettingsSheet(settings: Bindable(model.prompter).settings)
        }
        .sheet(item: $model.finishedTake) { take in
            TakeSummarySheet(take: take)
        }
        .task {
            interfaceOrientation = Self.currentOrientation()
            await model.prepare()
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { Task { await model.stopRecording() } }
        }
    }

    private func close() {
        Task {
            await model.teardown()
            dismiss()
        }
    }

    private static func currentOrientation() -> UIInterfaceOrientation {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.effectiveGeometry.interfaceOrientation ?? .portrait
    }
}

/// Where the script panel goes so the reader's eyes stay close to the lens.
struct LensPlacement: Equatable {
    var widthFraction: Double
    var heightFraction: Double
    var alignment: Alignment

    static func make(size: CGSize, orientation: UIInterfaceOrientation, isPad: Bool, camera: CameraPosition) -> LensPlacement {
        // Rear camera: someone else is behind the phone, so use the full stage.
        if camera == .back { return LensPlacement(widthFraction: 1, heightFraction: 1, alignment: .top) }
        // iPad front cameras sit on the top edge (portrait or landscape, depending on model).
        if isPad || size.height >= size.width {
            return LensPlacement(widthFraction: 1, heightFraction: 0.45, alignment: .top)
        }
        // iPhone in landscape: the front camera is on the left when the interface is
        // landscapeRight (home indicator on the right), on the right for landscapeLeft.
        let lensOnLeft = orientation == .landscapeRight
        return LensPlacement(widthFraction: 0.55, heightFraction: 1, alignment: lensOnLeft ? .topLeading : .topTrailing)
    }
}

struct CameraPreview: UIViewRepresentable {
    let view: UIView

    func makeUIView(context: Context) -> UIView { view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

private struct RecordButton: View {
    let isRecording: Bool
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(CueColor.stageText, lineWidth: 3)
                    .frame(width: 60, height: 60)
                RoundedRectangle(cornerRadius: isRecording ? 6 : 24)
                    .fill(CueColor.cueRed)
                    .frame(width: isRecording ? 24 : 48, height: isRecording ? 24 : 48)
            }
            .frame(width: 64, height: 64)
            .animation(.snappy(duration: 0.2), value: isRecording)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .opacity(isBusy ? 0.5 : 1)
        .accessibilityLabel(isRecording ? Text("Stop recording") : Text("Start recording"))
        .accessibilityIdentifier("recorder.record")
    }
}

private struct CameraMenu: View {
    let model: RecordingViewModel

    var body: some View {
        Menu {
            Button("Switch camera", systemImage: "arrow.triangle.2.circlepath.camera") {
                Task { await model.switchCamera() }
            }
            Picker("Resolution", selection: Binding(get: { model.camera.resolution }, set: { value in Task { await model.setResolution(value) } })) {
                ForEach(model.camera.supportedResolutions) { Text($0.label).tag($0) }
            }
            Picker("Frame rate", selection: Binding(get: { model.camera.frameRate }, set: { value in Task { await model.setFrameRate(value) } })) {
                ForEach(model.camera.supportedFrameRates(for: model.camera.resolution), id: \.self) { Text("\($0) fps").tag($0) }
            }
            if model.camera.audioInputs.count > 1 {
                Picker("Microphone", selection: Binding(get: { model.camera.selectedAudioInputID }, set: { model.camera.selectAudioInput(id: $0) })) {
                    ForEach(model.camera.audioInputs) { Text($0.name).tag(Optional($0.id)) }
                }
            }
        } label: {
            Image(systemName: "camera")
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.glass)
        .disabled(model.state.isRecording)
        .accessibilityLabel(Text("Camera options"))
        .accessibilityIdentifier("recorder.cameraOptions")
    }
}

private struct RecordingIndicator: View {
    let startedAt: Date

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: 1)) { context in
            let seconds = Int(context.date.timeIntervalSince(startedAt))
            HStack(spacing: CueSpacing.s) {
                Circle().fill(CueColor.cueRed).frame(width: 10, height: 10)
                Text(Duration.seconds(seconds), format: .time(pattern: .minuteSecond))
                    .monospacedDigit()
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CueColor.stageText)
            }
            .padding(.horizontal, CueSpacing.m)
            .padding(.vertical, CueSpacing.s)
            .glassEffect(.regular, in: .capsule)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Recording"))
        }
    }
}

private struct CameraProblem: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: CueSpacing.m) {
            Image(systemName: "video.slash")
                .font(.largeTitle)
                .foregroundStyle(CueColor.mist)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(CueColor.stageText)
            HStack {
                Button("Try again", action: retry)
                    .buttonStyle(.glass)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(.glass)
            }
        }
        .padding(CueSpacing.xl)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .padding(CueSpacing.xl)
    }
}
