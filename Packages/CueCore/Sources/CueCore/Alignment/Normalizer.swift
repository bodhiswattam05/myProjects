import Foundation

/// Turns written or recognised words into a form that can be compared.
public enum Normalizer {
    /// Lower-cases, folds accents and strips everything but letters and digits.
    /// "Don't" → "dont", "Café," → "cafe", "&" → "and". Returns "" for pure punctuation.
    public static func normalize(_ word: some StringProtocol) -> String {
        if word == "&" { return "and" }
        let folded = String(word).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        var result = ""
        result.reserveCapacity(folded.count)
        for scalar in folded.unicodeScalars where CharacterSet.alphanumerics.contains(scalar) {
            result.unicodeScalars.append(scalar)
        }
        return result.lowercased()
    }

    /// Splits free text (for example a recogniser transcript) into normalized words.
    public static func words(in text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace })
            .map { normalize($0) }
            .filter { !$0.isEmpty }
    }

    private static let numberWords: [String: String] = [
        "0": "zero", "1": "one", "2": "two", "3": "three", "4": "four", "5": "five",
        "6": "six", "7": "seven", "8": "eight", "9": "nine", "10": "ten", "11": "eleven",
        "12": "twelve", "13": "thirteen", "14": "fourteen", "15": "fifteen", "16": "sixteen",
        "17": "seventeen", "18": "eighteen", "19": "nineteen", "20": "twenty", "30": "thirty",
        "40": "forty", "50": "fifty", "60": "sixty", "70": "seventy", "80": "eighty",
        "90": "ninety", "100": "hundred", "1000": "thousand"
    ]

    /// Spelled-out form of a small number written as digits, so "3" matches "three".
    static func spelledNumber(_ word: String) -> String? {
        numberWords[word]
    }
}

/// Fuzzy word similarity in `0...1`, tolerant of recogniser spelling and mispronunciation.
public enum WordSimilarity {
    public static func score(_ a: String, _ b: String) -> Double {
        if a.isEmpty || b.isEmpty { return 0 }
        if a == b { return 1 }
        if let spelled = Normalizer.spelledNumber(a), spelled == b { return 1 }
        if let spelled = Normalizer.spelledNumber(b), spelled == a { return 1 }
        // Very short words ("a", "an", "to") must match exactly or they match everything.
        if min(a.count, b.count) <= 2 { return 0 }

        let distance = levenshtein(a, b)
        var score = 1 - Double(distance) / Double(max(a.count, b.count))
        if PhoneticKey.make(a) == PhoneticKey.make(b) {
            score = max(score, 0.85)
        }
        // Live (volatile) results often hold a word that is still being spoken: "presen" → "presentation".
        let (shorter, longer) = a.count < b.count ? (a, b) : (b, a)
        if shorter.count >= 4, longer.hasPrefix(shorter) {
            score = max(score, 0.8)
        }
        return score
    }

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a.unicodeScalars), b = Array(b.unicodeScalars)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}

/// A deliberately simple sound-alike key: keeps the first letter, merges consonants that
/// are often confused, and drops later vowels. Good enough to pair "colour"/"color" or
/// "fotograph"/"photograph"; not a full Metaphone.
enum PhoneticKey {
    static func make(_ word: String) -> String {
        var text = word
        for (from, to) in [("ph", "f"), ("ck", "k"), ("gh", "g"), ("th", "t"), ("sh", "s"), ("ch", "k"), ("wh", "w"), ("qu", "kw")] {
            text = text.replacingOccurrences(of: from, with: to)
        }
        var key = ""
        var last: Character?
        for (offset, character) in text.enumerated() {
            let mapped: Character
            switch character {
            case "c", "k", "q": mapped = "k"
            case "z", "s", "x": mapped = "s"
            case "d", "t": mapped = "t"
            case "b", "p": mapped = "p"
            case "v", "f": mapped = "f"
            case "j", "g": mapped = "g"
            case "m", "n": mapped = "n"
            case "a", "e", "i", "o", "u", "y", "h", "w":
                if offset == 0 { mapped = "a" } else { last = nil; continue }
            default: mapped = character
            }
            if mapped != last { key.append(mapped) }
            last = mapped
        }
        return key
    }
}
