import Foundation
import UIKit
import UniformTypeIdentifiers

/// Reads .txt, .md and .rtf files into script text.
enum ScriptImporter {
    struct Imported: Equatable {
        var title: String
        var body: String
    }

    enum ImportError: LocalizedError {
        case unreadable
        case empty

        var errorDescription: String? {
            switch self {
            case .unreadable: String(localized: "Cue can read plain text, Markdown and RTF files. This one couldn't be opened.")
            case .empty: String(localized: "This file has no text in it.")
            }
        }
    }

    static var contentTypes: [UTType] {
        [.plainText, .rtf, UTType(filenameExtension: "md") ?? .plainText, UTType("net.daringfireball.markdown") ?? .plainText]
    }

    static func read(_ url: URL) throws -> Imported {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ImportError.unreadable
        }
        let title = url.deletingPathExtension().lastPathComponent
        let body: String
        switch url.pathExtension.lowercased() {
        case "rtf":
            body = try rtfText(data)
        case "md", "markdown":
            body = markdownToScript(try plainText(data))
        default:
            body = try plainText(data)
        }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ImportError.empty }
        return Imported(title: title, body: trimmed)
    }

    static func plainText(_ data: Data) throws -> String {
        if let text = String(data: data, encoding: .utf8) { return text }
        if let text = String(data: data, encoding: .utf16) { return text }
        if let text = String(data: data, encoding: .isoLatin1) { return text }
        throw ImportError.unreadable
    }

    static func rtfText(_ data: Data) throws -> String {
        do {
            let attributed = try NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )
            return attributed.string
        } catch {
            throw ImportError.unreadable
        }
    }

    /// Keeps Markdown that maps onto Cue's markup and drops the rest:
    /// headings lose their `#`, `**bold**` and `_italic_` become `*emphasis*`, `---` stays a
    /// section break, and list markers are removed.
    static func markdownToScript(_ markdown: String) -> String {
        markdown
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                var text = String(line)
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#") {
                    text = String(trimmed.drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespaces)
                } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                    text = String(trimmed.dropFirst(2))
                } else if trimmed == "***" || trimmed == "___" {
                    text = "---"
                }
                text = text.replacingOccurrences(of: "**", with: "*")
                text = text.replacingOccurrences(of: "__", with: "*")
                return text
            }
            .joined(separator: "\n")
    }
}
