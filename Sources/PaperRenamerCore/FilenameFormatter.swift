import Foundation

/// How authors appear in the file name.
public enum AuthorStyle: String, CaseIterable, Identifiable {
    /// "Müller", "Müller & Schmidt", "Müller et al."
    case apa
    /// "Müller", "Müller et al."
    case firstEtAl
    /// "Müller"
    case firstOnly

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .apa: return "Müller · Müller & Schmidt · Müller et al."
        case .firstEtAl: return "Müller · Müller et al."
        case .firstOnly: return "Nur Erstautor: Müller"
        }
    }
}

/// Text between "(Jahr)" and the title.
public enum TitleSeparator: String, CaseIterable, Identifiable {
    case space = " "
    case dash = " - "
    case period = ". "

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .space: return "Müller (2021) Titel"
        case .dash: return "Müller (2021) - Titel"
        case .period: return "Müller (2021). Titel"
        }
    }
}

/// Builds "Autor (Jahr) Titel" file names.
public struct FilenameFormatter {
    public var authorStyle: AuthorStyle
    public var separator: TitleSeparator
    /// Maximum length of the name without ".pdf".
    public var maxLength: Int

    public init(authorStyle: AuthorStyle = .apa, separator: TitleSeparator = .space, maxLength: Int = 180) {
        self.authorStyle = authorStyle
        self.separator = separator
        self.maxLength = maxLength
    }

    /// "Müller", "Müller & Schmidt" or "Müller et al." depending on the style.
    public func authorText(_ authors: [Author]) -> String? {
        let names = authors.map(\.displayFamily).filter { !$0.isEmpty }
        guard let first = names.first else { return nil }
        switch authorStyle {
        case .firstOnly:
            return first
        case .firstEtAl:
            return names.count > 1 ? "\(first) et al." : first
        case .apa:
            switch names.count {
            case 1: return first
            case 2: return "\(first) & \(names[1])"
            default: return "\(first) et al."
            }
        }
    }

    /// Title cleaned up for display (markup removed, no ALL CAPS, no trailing period).
    public static func cleanTitle(_ title: String?) -> String? {
        guard let title = title else { return nil }
        var t = TextTools.fixShoutingCase(TextTools.stripMarkup(title))
        while t.hasSuffix(".") { t.removeLast() }
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// Makes a string safe for file names on macOS (and Windows/OneDrive).
    public static func sanitize(_ text: String) -> String {
        var s = text.precomposedStringWithCompatibilityMapping
        s = s.replacingOccurrences(of: #"[\r\n\t]+"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s*:\s+"#, with: " - ", options: .regularExpression)
        s = s.replacingOccurrences(of: ":", with: "-")
        s = s.replacingOccurrences(of: "/", with: "-")
        s = s.replacingOccurrences(of: "\\", with: "-")
        s = s.replacingOccurrences(of: "\"", with: "'")
        s = s.replacingOccurrences(of: "“", with: "'")
        s = s.replacingOccurrences(of: "”", with: "'")
        s = s.replacingOccurrences(of: #"[?*<>|]"#, with: "", options: .regularExpression)
        s = String(s.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
        s = TextTools.collapseWhitespace(s)
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: " -"))
        while s.hasPrefix(".") { s.removeFirst() }
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// Shortens text at a word boundary so it has at most `limit` characters.
    static func truncate(_ text: String, to limit: Int) -> String {
        guard text.count > limit, limit > 0 else { return text }
        let cut = String(text.prefix(limit))
        if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) > limit / 2 {
            return String(cut[..<space]).trimmingCharacters(in: CharacterSet(charactersIn: " .,;-–"))
        }
        return cut.trimmingCharacters(in: CharacterSet(charactersIn: " .,;-–"))
    }

    /// "Autor (Jahr) Titel" from already formatted parts. Returns nil if a part is missing.
    public func baseName(author: String, year: String, title: String) -> String? {
        let a = Self.sanitize(author)
        let y = Self.sanitize(year)
        var t = Self.sanitize(title)
        guard !a.isEmpty, !y.isEmpty, !t.isEmpty else { return nil }
        let prefix = "\(a) (\(y))\(separator.rawValue)"
        // Respect both the configured length and the 255-byte limit of APFS (incl. ".pdf").
        var available = max(20, maxLength - prefix.count)
        t = Self.truncate(t, to: available)
        while (prefix + t).utf8.count > 250, available > 10 {
            available -= 10
            t = Self.truncate(t, to: available)
        }
        return prefix + t
    }

    /// File name (without extension) for complete metadata, otherwise nil.
    public func baseName(for meta: PaperMetadata) -> String? {
        guard let author = authorText(meta.authors),
              let year = meta.year,
              let title = Self.cleanTitle(meta.title) else { return nil }
        return baseName(author: author, year: year, title: title)
    }

    /// Appends " (2)", " (3)", ... until `exists` reports a free name.
    public static func uniqueFileName(base: String, ext: String, exists: (String) -> Bool) -> String {
        let suffix = ext.isEmpty ? "" : ".\(ext)"
        var name = base + suffix
        var counter = 2
        while exists(name), counter < 1000 {
            name = "\(base) (\(counter))\(suffix)"
            counter += 1
        }
        return name
    }
}
