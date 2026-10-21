/// Word-level difference between two texts, for showing a suggested rewrite before the
/// user accepts it. Whitespace isn't significant; punctuation is part of each word.
public enum WordDiff {
    public enum Kind: Sendable, Equatable {
        case same
        case removed
        case added
    }

    public struct Token: Sendable, Equatable {
        public var kind: Kind
        public var text: String

        public init(kind: Kind, text: String) {
            self.kind = kind
            self.text = text
        }
    }

    /// Tokens in reading order: unchanged words, with removals shown before the words
    /// that replace them. Neighbouring tokens of the same kind are merged.
    public static func tokens(from original: String, to revised: String) -> [Token] {
        let old = original.split(whereSeparator: \.isWhitespace).map(String.init)
        let new = revised.split(whereSeparator: \.isWhitespace).map(String.init)
        let n = old.count, m = new.count

        // Longest common subsequence table, filled from the end.
        var table = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        if n > 0 && m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    table[i][j] = old[i] == new[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
                }
            }
        }

        var raw: [Token] = []
        var i = 0, j = 0
        while i < n || j < m {
            if i < n, j < m, old[i] == new[j] {
                raw.append(Token(kind: .same, text: old[i]))
                i += 1
                j += 1
            } else if i < n, j == m || table[i + 1][j] >= table[i][j + 1] {
                raw.append(Token(kind: .removed, text: old[i]))
                i += 1
            } else {
                raw.append(Token(kind: .added, text: new[j]))
                j += 1
            }
        }

        var merged: [Token] = []
        for token in raw {
            if let last = merged.last, last.kind == token.kind {
                merged[merged.count - 1].text += " " + token.text
            } else {
                merged.append(token)
            }
        }
        return merged
    }

    /// True when the revision changes nothing but whitespace.
    public static func isUnchanged(_ original: String, _ revised: String) -> Bool {
        tokens(from: original, to: revised).allSatisfy { $0.kind == .same }
    }
}
