import Foundation
import PaperRenamerCore

/// Command line mode, mainly for testing:
///
///     PaperRenamer --cli [--rename] [--offline] [--debug] datei.pdf ...
///
/// Without `--rename` the proposed names are only printed.
enum CLI {
    static func run(arguments: [String]) async -> Int32 {
        let rename = arguments.contains("--rename")
        let offline = arguments.contains("--offline")
        let debug = arguments.contains("--debug")
        let files = arguments.filter { !$0.hasPrefix("--") }
        guard !files.isEmpty else {
            print("Aufruf: PaperRenamer --cli [--rename] [--offline] [--debug] datei.pdf ...")
            return 2
        }

        let settings = AppSettings.current
        let formatter = settings.formatter
        let resolver = MetadataResolver()
        var exitCode: Int32 = 0

        for path in files {
            let url = URL(fileURLWithPath: path).standardizedFileURL
            print("• \(url.lastPathComponent)")
            let info: PDFInfo
            do {
                info = try PDFInspector.inspect(url: url)
            } catch {
                print("  Fehler: \(error.localizedDescription)")
                exitCode = 1
                continue
            }

            if debug {
                print("  [debug] Metadaten-Titel: \(info.metadataTitle ?? "–")")
                print("  [debug] Metadaten-Autor: \(info.metadataAuthor ?? "–")")
                print("  [debug] XMP-DOIs: \(info.xmpDOIs)")
                print("  [debug] DOI-Kandidaten: \(IdentifierExtractor.doiCandidates(for: info).map(\.doi))")
                print("  [debug] arXiv: \(IdentifierExtractor.arxivID(in: info.text) ?? "–")")
                let detected = TextHeuristics.detectTitle(lines: info.lines)
                print("  [debug] Erkannter Titel: \(detected?.title ?? "–")")
                for line in info.lines.prefix(12) {
                    let position = String(format: "%5.1fpt  %.2f", line.fontSize, line.top)
                    print("  [debug]   \(position)  \(line.text.prefix(90))")
                }
                let estimate = resolver.offlineMetadata(info)
                print("  [debug] Offline-Schätzung: \(formatter.baseName(for: estimate) ?? "unvollständig")")
            }

            let meta = await resolver.resolve(info, online: !offline)
            guard let base = formatter.baseName(for: meta) else {
                print("  → unvollständig (Autor: \(formatter.authorText(meta.authors) ?? "–"), Jahr: \(meta.year ?? "–"), Titel: \(meta.title ?? "–"))")
                exitCode = 1
                continue
            }
            print("  → \(base).pdf")
            print("    Quelle: \(RenameController.describe(meta))")

            if rename {
                do {
                    let newURL = try FileRenamer.rename(url, toBaseName: base)
                    print("    umbenannt: \(newURL.lastPathComponent)")
                } catch {
                    print("    Fehler beim Umbenennen: \(error.localizedDescription)")
                    exitCode = 1
                }
            }
        }
        return exitCode
    }
}
