import AppKit
import Foundation
import PaperRenamerCore
import UniformTypeIdentifiers

/// One dropped file and what happened to it.
struct RenameItem: Identifiable, Equatable {
    enum Status: Equatable {
        case analyzing
        case renamed
        case alreadyNamed
        case needsReview
        case needsInput
        case failed(String)
        case undone
    }

    let id = UUID()
    let originalURL: URL
    var currentURL: URL
    var status: Status = .analyzing
    var authorText = ""
    var yearText = ""
    var titleText = ""
    /// True if the data was confirmed online (DOI, arXiv, Crossref).
    var verified = false
    var sourceNote = ""

    init(url: URL) {
        originalURL = url
        currentURL = url
    }

    var isBusy: Bool { status == .analyzing }
    var canUndo: Bool { currentURL != originalURL && status != .undone }
}

@MainActor
final class RenameController: ObservableObject {
    static let shared = RenameController()

    @Published private(set) var items: [RenameItem] = []

    private let resolver = MetadataResolver()
    private var queue: [UUID] = []
    private var activeWorkers = 0
    private let maxWorkers = 3

    // MARK: - Input

    /// Accepts dropped files and folders (PDFs directly inside dropped folders are included).
    func handle(urls: [URL]) {
        var pdfs: [URL] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                let contents = (try? FileManager.default.contentsOfDirectory(
                    at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
                )) ?? []
                pdfs += contents.filter(Self.isPDF).sorted { $0.lastPathComponent < $1.lastPathComponent }
            } else if Self.isPDF(url) {
                pdfs.append(url)
            } else {
                var item = RenameItem(url: url)
                item.status = .failed("Keine PDF-Datei – wurde übersprungen.")
                items.insert(item, at: 0)
            }
        }

        for url in pdfs {
            let standardized = url.standardizedFileURL
            if items.contains(where: { $0.currentURL.standardizedFileURL == standardized && $0.isBusy }) {
                continue
            }
            let item = RenameItem(url: standardized)
            items.insert(item, at: 0)
            queue.append(item.id)
        }
        startWorkers()
    }

    static func isPDF(_ url: URL) -> Bool {
        if url.pathExtension.lowercased() == "pdf" { return true }
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return type.conforms(to: .pdf)
        }
        return false
    }

    func choosePDFs() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.pdf, .folder]
        panel.prompt = "Umbenennen"
        panel.message = "Wähle PDFs (oder Ordner mit PDFs), die umbenannt werden sollen."
        if panel.runModal() == .OK {
            handle(urls: panel.urls)
        }
    }

    // MARK: - Processing

    private func startWorkers() {
        while activeWorkers < maxWorkers, !queue.isEmpty {
            activeWorkers += 1
            Task { @MainActor in
                while !self.queue.isEmpty {
                    let id = self.queue.removeFirst()
                    await self.process(id)
                }
                self.activeWorkers -= 1
            }
        }
    }

    private func index(of id: UUID) -> Int? {
        items.firstIndex { $0.id == id }
    }

    private func update(_ id: UUID, _ change: (inout RenameItem) -> Void) {
        guard let i = index(of: id) else { return }
        change(&items[i])
    }

    private func process(_ id: UUID) async {
        guard let item = items.first(where: { $0.id == id }) else { return }
        let url = item.currentURL
        let settings = AppSettings.current

        let info: PDFInfo
        do {
            info = try await Task.detached(priority: .userInitiated) {
                try PDFInspector.inspect(url: url)
            }.value
        } catch {
            update(id) { $0.status = .failed(error.localizedDescription) }
            return
        }

        let meta = await resolver.resolve(info, online: settings.onlineLookup)
        let formatter = settings.formatter

        update(id) { item in
            item.authorText = formatter.authorText(meta.authors) ?? ""
            item.yearText = meta.year ?? ""
            item.titleText = FilenameFormatter.cleanTitle(meta.title) ?? ""
            item.verified = meta.isVerified
            item.sourceNote = Self.describe(meta)
        }

        guard let current = items.first(where: { $0.id == id }) else { return }
        if formatter.baseName(author: current.authorText, year: current.yearText, title: current.titleText) == nil {
            update(id) { $0.status = .needsInput }
        } else if current.verified || settings.autoRenameUncertain {
            performRename(id)
        } else {
            update(id) { $0.status = .needsReview }
        }
    }

    nonisolated static func describe(_ meta: PaperMetadata) -> String {
        switch meta.source {
        case .doi: return "über DOI \(meta.identifier ?? "") bestätigt"
        case .arxiv: return "über arXiv bestätigt"
        case .crossrefSearch: return "über Crossref gefunden"
        case .offline: return "nur aus der PDF geschätzt – bitte prüfen"
        }
    }

    // MARK: - Actions

    private func performRename(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        let formatter = AppSettings.current.formatter
        guard let base = formatter.baseName(author: item.authorText, year: item.yearText, title: item.titleText) else {
            update(id) { $0.status = .needsInput }
            return
        }
        do {
            let oldName = item.currentURL.lastPathComponent
            let newURL = try FileRenamer.rename(item.currentURL, toBaseName: base)
            update(id) {
                $0.currentURL = newURL
                $0.status = newURL.lastPathComponent == oldName && newURL == item.originalURL
                    ? .alreadyNamed : .renamed
            }
        } catch {
            update(id) { $0.status = .failed(error.localizedDescription) }
        }
    }

    /// Applies manually edited values and renames the file.
    func applyEdit(id: UUID, author: String, year: String, title: String) {
        update(id) {
            $0.authorText = author.trimmingCharacters(in: .whitespacesAndNewlines)
            $0.yearText = year.trimmingCharacters(in: .whitespacesAndNewlines)
            $0.titleText = title.trimmingCharacters(in: .whitespacesAndNewlines)
            $0.verified = true
            $0.sourceNote = "manuell bearbeitet"
        }
        performRename(id)
    }

    /// Restores the original file name.
    func undo(id: UUID) {
        guard let item = items.first(where: { $0.id == id }), item.canUndo else { return }
        let originalBase = item.originalURL.deletingPathExtension().lastPathComponent
        do {
            let restored = try FileRenamer.rename(item.currentURL, toBaseName: originalBase)
            update(id) {
                $0.currentURL = restored
                $0.status = .undone
            }
        } catch {
            update(id) { $0.status = .failed(error.localizedDescription) }
        }
    }

    func revealInFinder(id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([item.currentURL])
    }

    func open(id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        NSWorkspace.shared.open(item.currentURL)
    }

    func clearFinished() {
        items.removeAll { !$0.isBusy }
    }

    func item(id: UUID) -> RenameItem? {
        items.first { $0.id == id }
    }
}
