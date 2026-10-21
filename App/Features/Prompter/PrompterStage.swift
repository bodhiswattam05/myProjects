import CueCore
import SwiftUI
import UIKit

/// The stage: script, reading line and gestures. No chrome. Used by the prompter screen
/// on its own and by the recorder on top of the camera preview.
struct PrompterStage: View {
    @Bindable var model: PrompterViewModel
    /// Draw the slate background. Off when the camera preview sits behind.
    var showsBackground = true
    /// Fraction of the stage width the text may use (before margins).
    var columnWidthFraction: Double = 1
    /// Which side the narrowed column hugs, to keep the text near the camera lens.
    var columnAlignment: Alignment = .center

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let columnWidth = size.width * columnWidthFraction
            let margin = columnWidth * model.settings.margin
            let readingY = size.height * model.settings.readingLinePosition
            let bandPadding = model.settings.fontSize * 0.3

            ZStack(alignment: .topLeading) {
                if showsBackground {
                    CueColor.stage
                }
                ZStack(alignment: .topLeading) {
                    StageTextColumn(
                        document: model.document,
                        settings: model.settings,
                        palette: .make(highContrast: contrast == .increased),
                        dimming: dimming,
                        onLineFrame: { [model] id, frame in model.setLineFrame(id, frame: frame) }
                    )
                    .equatable()
                    .frame(width: max(columnWidth - margin * 2, 1))
                    .fixedSize(horizontal: false, vertical: true)
                    .offset(x: margin, y: readingY - model.offset)

                    ReadingLine(height: model.lineHeight + bandPadding, isActive: model.phase == .running)
                        .frame(width: columnWidth)
                        .offset(y: readingY - bandPadding / 2)
                }
                .frame(width: columnWidth, height: size.height, alignment: .topLeading)
                .scaleEffect(x: model.settings.isMirrored ? -1 : 1, y: 1)
                .frame(width: size.width, height: size.height, alignment: columnAlignment)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                model.jumpToNextSection()
            }
            .onTapGesture {
                model.togglePlayPause()
                model.noteInteraction()
            }
            .gesture(
                TwoFingerPan(
                    onBegan: { model.beginScrub() },
                    onChanged: { model.scrub(by: $0) },
                    onEnded: { model.endScrub() }
                )
            )
            .onAppear { model.setStageHeight(size.height) }
            .onChange(of: size.height) { _, height in model.setStageHeight(height) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Prompter"))
        .accessibilityValue(Text(currentLineText))
        .accessibilityHint(Text("Double-tap to play or pause."))
        .accessibilityAddTraits(.allowsDirectInteraction)
        .accessibilityAction { model.togglePlayPause() }
        .accessibilityAction(named: Text("Next section")) { model.jumpToNextSection() }
        .accessibilityAction(named: Text("Previous section")) { model.jumpToPreviousSection() }
        .sensoryFeedback(.selection, trigger: model.sectionJumpCount)
    }

    private var dimming: StageDimming {
        if model.effectivePacing == .voice {
            return .words(through: model.spokenThrough)
        }
        var read = Set<Int>()
        for section in model.document.sections {
            for line in section.lines where model.isLineRead(line.id) {
                read.insert(line.id)
            }
        }
        return .lines(read)
    }

    private var currentLineText: String {
        guard let id = model.currentLineID,
              let line = model.document.sections.lazy.flatMap(\.lines).first(where: { $0.id == id }) else { return "" }
        return line.runs.compactMap { run -> String? in
            if case let .word(_, text, _) = run { text } else { nil }
        }.joined(separator: " ")
    }
}

/// Two-finger vertical drag, for scrubbing without fighting the one-finger taps.
struct TwoFingerPan: UIGestureRecognizerRepresentable {
    var onBegan: () -> Void
    var onChanged: (Double) -> Void
    var onEnded: () -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.minimumNumberOfTouches = 2
        recognizer.maximumNumberOfTouches = 2
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began:
            onBegan()
        case .changed:
            onChanged(recognizer.translation(in: recognizer.view).y)
        case .ended, .cancelled, .failed:
            onEnded()
        default:
            break
        }
    }
}

#Preview("Stage") {
    let model = PrompterViewModel(title: "Welcome", text: SampleData.scripts[0].body, settings: PrompterSettings(), speech: nil)
    PrompterStage(model: model)
        .ignoresSafeArea()
}
