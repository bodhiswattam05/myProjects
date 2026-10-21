import Foundation

/// Everything that controls how the stage looks and moves. Saved inside presets.
struct PrompterSettings: Codable, Equatable, Sendable {
    enum Pacing: String, Codable, CaseIterable, Identifiable, Sendable {
        /// Scrolls at a steady speed you set.
        case manual
        /// Follows your voice.
        case voice

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .manual: String(localized: "Steady")
            case .voice: String(localized: "Follow my voice")
            }
        }
    }

    enum Alignment: String, Codable, CaseIterable, Identifiable, Sendable {
        case leading
        case center

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .leading: String(localized: "Left")
            case .center: String(localized: "Centered")
            }
        }
    }

    static let fontSizeRange: ClosedRange<Double> = 24...120
    static let lineSpacingRange: ClosedRange<Double> = 0.1...1.0
    static let marginRange: ClosedRange<Double> = 0.02...0.3
    static let speedRange: ClosedRange<Double> = 0.5...10
    static let readingLineRange: ClosedRange<Double> = 0.12...0.7

    var fontSize: Double = 44
    /// Extra space between lines, as a fraction of the font size.
    var lineSpacing: Double = 0.35
    /// Side margins, as a fraction of the stage width.
    var margin: Double = 0.08
    /// Steady scroll speed, 0.5–10. One unit is roughly a quarter of a line per second.
    var speed: Double = 3
    var alignment: Alignment = .leading
    /// Horizontal flip for beam-splitter rigs.
    var isMirrored: Bool = false
    /// Where the reading line sits, as a fraction of the stage height from the top.
    var readingLinePosition: Double = 0.33
    var typeface: PrompterTypeface = .sfPro
    var pacing: Pacing = .manual
    var countdownSeconds: Int = 3

    /// Points per second for steady scrolling at this font size.
    var pointsPerSecond: Double {
        speed * fontSize * (1 + lineSpacing) * 0.25
    }

    init() {}

    // Decoding tolerates missing keys, so presets saved by older builds still load.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = PrompterSettings()
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? defaults.fontSize
        lineSpacing = try container.decodeIfPresent(Double.self, forKey: .lineSpacing) ?? defaults.lineSpacing
        margin = try container.decodeIfPresent(Double.self, forKey: .margin) ?? defaults.margin
        speed = try container.decodeIfPresent(Double.self, forKey: .speed) ?? defaults.speed
        alignment = try container.decodeIfPresent(Alignment.self, forKey: .alignment) ?? defaults.alignment
        isMirrored = try container.decodeIfPresent(Bool.self, forKey: .isMirrored) ?? defaults.isMirrored
        readingLinePosition = try container.decodeIfPresent(Double.self, forKey: .readingLinePosition) ?? defaults.readingLinePosition
        typeface = try container.decodeIfPresent(PrompterTypeface.self, forKey: .typeface) ?? defaults.typeface
        pacing = try container.decodeIfPresent(Pacing.self, forKey: .pacing) ?? defaults.pacing
        countdownSeconds = try container.decodeIfPresent(Int.self, forKey: .countdownSeconds) ?? defaults.countdownSeconds
    }

    // MARK: Built-in presets

    static var rigMode: PrompterSettings {
        var settings = PrompterSettings()
        settings.fontSize = 64
        settings.isMirrored = true
        settings.margin = 0.12
        settings.alignment = .center
        settings.readingLinePosition = 0.4
        return settings
    }

    static var selfieMode: PrompterSettings {
        var settings = PrompterSettings()
        settings.fontSize = 34
        settings.margin = 0.06
        settings.readingLinePosition = 0.18
        settings.pacing = .voice
        return settings
    }

    static var rehearsal: PrompterSettings {
        var settings = PrompterSettings()
        settings.fontSize = 44
        settings.pacing = .voice
        settings.typeface = .newYork
        return settings
    }
}
