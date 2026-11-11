import AppKit
import Foundation
import PaperRenamerCore
import PDFKit

enum PDFInspectorError: LocalizedError {
    case unreadable
    case locked

    var errorDescription: String? {
        switch self {
        case .unreadable: return "Die Datei ist keine lesbare PDF."
        case .locked: return "Die PDF ist passwortgeschützt."
        }
    }
}

/// Reads metadata and first-page text of a PDF with PDFKit.
enum PDFInspector {
    static func inspect(url: URL) throws -> PDFInfo {
        guard let document = PDFDocument(url: url) else { throw PDFInspectorError.unreadable }
        if document.isLocked, !document.unlock(withPassword: "") {
            throw PDFInspectorError.locked
        }

        let attributes = document.documentAttributes ?? [:]
        func attribute(_ key: PDFDocumentAttribute) -> String? {
            guard let value = attributes[key] as? String else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        var keywords: [String] = []
        if let list = attributes[PDFDocumentAttribute.keywordsAttribute] as? [String] {
            keywords = list
        } else if let single = attributes[PDFDocumentAttribute.keywordsAttribute] as? String {
            keywords = [single]
        }
        var creationYear: String?
        if let date = attributes[PDFDocumentAttribute.creationDateAttribute] as? Date {
            creationYear = String(Calendar(identifier: .gregorian).component(.year, from: date))
        }

        var text = ""
        for index in 0..<min(document.pageCount, 2) {
            if let pageText = document.page(at: index)?.string {
                text += pageText + "\n"
            }
        }

        var lines: [TextLine] = []
        if let page = document.page(at: 0) {
            lines = extractLines(from: page)
        }

        var xmpDOIs: [String] = []
        if let data = try? Data(contentsOf: url, options: .mappedIfSafe) {
            xmpDOIs = IdentifierExtractor.xmpDOIs(in: data)
        }

        return PDFInfo(
            fileName: url.lastPathComponent,
            metadataTitle: attribute(.titleAttribute),
            metadataAuthor: attribute(.authorAttribute),
            metadataSubject: attribute(.subjectAttribute),
            metadataKeywords: keywords,
            creationYear: creationYear,
            lines: lines,
            text: text,
            xmpDOIs: xmpDOIs
        )
    }

    /// The text lines of a page with their dominant font size and vertical position.
    static func extractLines(from page: PDFPage) -> [TextLine] {
        let pageBounds = page.bounds(for: .cropBox)
        guard pageBounds.height > 0, let selection = page.selection(for: pageBounds) else { return [] }

        var result: [TextLine] = []
        for line in selection.selectionsByLine() {
            guard let raw = line.string else { continue }
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let bounds = line.bounds(for: page)

            // Font size that covers the most characters of the line.
            var sizes: [CGFloat: Int] = [:]
            if let attributed = line.attributedString, attributed.length > 0 {
                attributed.enumerateAttribute(
                    .font, in: NSRange(location: 0, length: attributed.length), options: []
                ) { value, range, _ in
                    if let font = value as? NSFont {
                        let size = (font.pointSize * 2).rounded() / 2
                        sizes[size, default: 0] += range.length
                    }
                }
            }
            var fontSize = sizes.max { $0.value < $1.value }?.key ?? 0
            if fontSize <= 0 { fontSize = bounds.height * 0.8 }

            let top = (pageBounds.maxY - bounds.maxY) / pageBounds.height
            result.append(TextLine(text: text, fontSize: Double(fontSize), top: Double(max(0, min(1, top)))))
        }
        return result
    }
}
