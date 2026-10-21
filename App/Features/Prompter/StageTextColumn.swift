import CueCore
import SwiftUI

/// What's already been read, for dimming.
enum StageDimming: Equatable {
    /// Steady pacing: whole lines that have scrolled above the reading band.
    case lines(Set<Int>)
    /// Voice pacing: every word up to and including this index.
    case words(through: Int)
}

/// The script, laid out for the stage. Only re-renders when its inputs change (dimming
/// moves a line or a word at a time), not on every scroll frame.
struct StageTextColumn: View, Equatable {
    nonisolated static let coordinateSpace = "stage-content"

    let document: ScriptDocument
    let settings: PrompterSettings
    let palette: StagePalette
    let dimming: StageDimming
    let onLineFrame: @MainActor (Int, CGRect) -> Void

    nonisolated static func == (lhs: StageTextColumn, rhs: StageTextColumn) -> Bool {
        lhs.document == rhs.document && lhs.settings == rhs.settings && lhs.palette == rhs.palette && lhs.dimming == rhs.dimming
    }

    var body: some View {
        VStack(alignment: horizontalAlignment, spacing: settings.fontSize * settings.lineSpacing) {
            ForEach(Array(document.sections.enumerated()), id: \.element.id) { index, section in
                if index > 0 {
                    SectionBreak(color: palette.read, fontSize: settings.fontSize)
                }
                ForEach(section.lines) { line in
                    lineView(line)
                }
            }
            if document.sections.isEmpty {
                Text("This script is empty. Add some words in the editor.")
                    .font(settings.typeface.font(size: settings.fontSize * 0.6))
                    .foregroundStyle(palette.note)
            }
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
        .coordinateSpace(.named(Self.coordinateSpace))
    }

    private func lineView(_ line: ScriptLine) -> some View {
        Text(attributed(line))
            .font(settings.typeface.font(size: settings.fontSize))
            .lineSpacing(settings.fontSize * (settings.lineSpacing * 0.5 + settings.typeface.extraLeading))
            .multilineTextAlignment(settings.alignment == .center ? .center : .leading)
            .frame(maxWidth: .infinity, alignment: frameAlignment)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(Self.coordinateSpace))
            } action: { frame in
                onLineFrame(line.id, frame)
            }
            .accessibilityHidden(true)
    }

    private func attributed(_ line: ScriptLine) -> AttributedString {
        let lineRead: Bool = if case let .lines(read) = dimming { read.contains(line.id) } else { false }
        var result = AttributedString()
        var first = true
        for run in line.runs {
            var piece: AttributedString
            switch run {
            case let .word(index, text, emphasized):
                piece = AttributedString(text)
                let read: Bool = if case let .words(through) = dimming { index <= through } else { lineRead }
                piece.foregroundColor = read ? palette.read : (emphasized ? palette.emphasis : palette.upcoming)
                if emphasized { piece.underlineStyle = .single }
            case let .literal(text):
                piece = AttributedString(text)
                piece.foregroundColor = lineRead ? palette.read : palette.upcoming
            case let .cue(cue):
                piece = AttributedString(cue == .pause ? String(localized: "pause") : String(localized: "breathe"))
                piece.foregroundColor = palette.cue
                piece.font = settings.typeface.font(size: settings.fontSize * 0.45).smallCaps()
            case let .note(text):
                piece = AttributedString(text)
                piece.foregroundColor = palette.note
                piece.font = settings.typeface.font(size: settings.fontSize * 0.5).italic()
            }
            if !first { result.append(AttributedString(" ")) }
            result.append(piece)
            first = false
        }
        return result
    }

    private var horizontalAlignment: HorizontalAlignment {
        settings.alignment == .center ? .center : .leading
    }

    private var frameAlignment: Alignment {
        settings.alignment == .center ? .center : .leading
    }
}

private struct SectionBreak: View {
    let color: Color
    let fontSize: Double

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: 48, height: 2)
            .frame(maxWidth: .infinity)
            .padding(.vertical, fontSize * 0.4)
            .accessibilityHidden(true)
    }
}

#Preview("Text column") {
    let document = ScriptParser.parse(SampleData.scripts[0].body)
    ScrollView {
        StageTextColumn(
            document: document,
            settings: PrompterSettings(),
            palette: .make(highContrast: false),
            dimming: .words(through: 12),
            onLineFrame: { _, _ in }
        )
        .padding(32)
    }
    .background(CueColor.stage)
}
