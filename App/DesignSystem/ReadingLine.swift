import SwiftUI

/// The signature element: a soft tungsten glow band where the current line sits.
///
/// - Increase Contrast swaps the glow for a solid 2 pt rule plus a flat band.
/// - Reduce Motion keeps the band perfectly still (no breathing glow).
struct ReadingLine: View {
    /// Height of the band, usually one line of prompter text.
    var height: CGFloat
    var isActive: Bool

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if contrast == .increased {
                ZStack {
                    Rectangle().fill(CueColor.tungsten.opacity(0.16))
                    VStack {
                        Rectangle().fill(CueColor.tungsten).frame(height: 2)
                        Spacer(minLength: 0)
                        Rectangle().fill(CueColor.tungsten).frame(height: 2)
                    }
                }
            } else {
                glow
            }
        }
        .frame(height: height)
        .opacity(isActive ? 1 : 0.6)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: isActive)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var glow: some View {
        LinearGradient(
            stops: [
                .init(color: CueColor.tungsten.opacity(0), location: 0),
                .init(color: CueColor.tungsten.opacity(0.14), location: 0.3),
                .init(color: CueColor.tungsten.opacity(0.18), location: 0.5),
                .init(color: CueColor.tungsten.opacity(0.14), location: 0.7),
                .init(color: CueColor.tungsten.opacity(0), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .blur(radius: 12)
        .padding(.vertical, -12)
        .overlay(alignment: .leading) {
            // A small tungsten tick at the margin so the eye finds the line instantly.
            Capsule()
                .fill(CueColor.tungsten)
                .frame(width: 4, height: height * 0.5)
                .padding(.leading, 6)
        }
    }
}

#Preview("Reading line") {
    ZStack {
        CueColor.stage.ignoresSafeArea()
        ReadingLine(height: 64, isActive: true)
    }
}
