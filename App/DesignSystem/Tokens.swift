import SwiftUI
import UIKit

/// Cue's colour tokens. Each one adapts to light/dark and to Increase Contrast.
///
/// Changes from the starting palette (see the plan):
/// - `mistLight` (#6B7079): Mist on Paper is about 3:1, too faint for body text.
/// - `tungstenDeep` (#A8661A): Tungsten text on Paper is about 1.7:1. In light mode Tungsten
///   is only a fill behind Ink text; tinted text and icons use Tungsten-deep.
/// - `stageText` (#ECEDEF): slightly off-white, less halation on beam-splitter glass.
enum CueColor {
    static let stage = Color(hex: 0x1A1D24)
    static let paper = Color(hex: 0xF7F7F5)
    static let ink = Color(hex: 0x1C1C1E)
    static let tungsten = Color(hex: 0xF2B25C)
    static let tungstenDeep = Color(hex: 0xA8661A)
    static let cueRed = Color(hex: 0xE5484D)
    static let mist = Color(hex: 0x8A8F98)
    static let mistLight = Color(hex: 0x6B7079)
    static let stageText = Color(hex: 0xECEDEF)

    /// Library and editor background: Paper in light mode, system background in dark.
    static let background = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .systemBackground : UIColor(hex: 0xF7F7F5)
    })

    /// Primary text in the library: Ink in light mode.
    static let primaryText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .label : UIColor(hex: 0x1C1C1E)
    })

    /// Secondary text: Mist-light on Paper, Mist on dark, both stronger with Increase Contrast.
    static let secondaryText = Color(uiColor: UIColor { traits in
        let high = traits.accessibilityContrast == .high
        if traits.userInterfaceStyle == .dark {
            return high ? UIColor(hex: 0xB4B8BF) : UIColor(hex: 0x8A8F98)
        }
        return high ? UIColor(hex: 0x4A4E55) : UIColor(hex: 0x6B7079)
    })

    /// Tinted text and icons: Tungsten-deep in light mode, Tungsten in dark.
    static let accent = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark { return UIColor(hex: 0xF2B25C) }
        return traits.accessibilityContrast == .high ? UIColor(hex: 0x8A5210) : UIColor(hex: 0xA8661A)
    })
}

/// Stage colours. The stage is always dark, so these don't follow the colour scheme.
struct StagePalette: Equatable {
    var upcoming: Color
    var read: Color
    var note: Color
    var cue: Color
    var emphasis: Color

    static func make(highContrast: Bool) -> StagePalette {
        StagePalette(
            upcoming: CueColor.stageText,
            read: CueColor.mist.opacity(highContrast ? 0.85 : 0.5),
            note: CueColor.mist.opacity(highContrast ? 0.9 : 0.6),
            cue: CueColor.tungsten.opacity(highContrast ? 1 : 0.8),
            emphasis: highContrast ? .white : CueColor.tungsten
        )
    }
}

enum CueSpacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 40
}

/// The prompter's typefaces: SF Pro (semibold) or New York (serif, a little more leading).
enum PrompterTypeface: String, CaseIterable, Identifiable, Codable {
    case sfPro
    case newYork

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sfPro: "SF Pro"
        case .newYork: "New York"
        }
    }

    func font(size: CGFloat) -> Font {
        switch self {
        case .sfPro: .system(size: size, weight: .semibold, design: .default)
        case .newYork: .system(size: size, weight: .medium, design: .serif)
        }
    }

    /// Extra line spacing New York needs to read as evenly as SF Pro.
    var extraLeading: CGFloat {
        switch self {
        case .sfPro: 0
        case .newYork: 0.08
        }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
