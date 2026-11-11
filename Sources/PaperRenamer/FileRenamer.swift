import Darwin
import Foundation
import PaperRenamerCore

enum FileRenamerError: LocalizedError {
    case missing
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .missing: return "Die Datei wurde verschoben oder gelöscht."
        case .failed(let message): return message
        }
    }
}

/// Renames files without ever overwriting another file.
enum FileRenamer {
    /// Renames `url` to `baseName.pdf` in the same folder and returns the new URL.
    /// If the name is taken by another file, " (2)", " (3)", ... is appended.
    static func rename(_ url: URL, toBaseName baseName: String) throws -> URL {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { throw FileRenamerError.missing }

        let folder = url.deletingLastPathComponent()
        let ext = url.pathExtension.isEmpty ? "pdf" : url.pathExtension.lowercased()
        let newName = FilenameFormatter.uniqueFileName(base: baseName, ext: ext) { name in
            let candidate = folder.appendingPathComponent(name)
            if candidate.lastPathComponent == url.lastPathComponent { return false }
            guard fileManager.fileExists(atPath: candidate.path) else { return false }
            // Same file with different upper/lower case counts as free.
            return !isSameFile(candidate, url)
        }
        let target = folder.appendingPathComponent(newName)
        if target.lastPathComponent == url.lastPathComponent { return url }

        if fileManager.fileExists(atPath: target.path) {
            // Only a change of upper/lower case on a case-insensitive volume.
            if Darwin.rename(url.path, target.path) != 0 {
                throw FileRenamerError.failed(String(cString: strerror(errno)))
            }
        } else {
            do {
                try fileManager.moveItem(at: url, to: target)
            } catch {
                throw FileRenamerError.failed(Self.describe(error))
            }
        }
        return target
    }

    static func isSameFile(_ a: URL, _ b: URL) -> Bool {
        let key: Set<URLResourceKey> = [.fileResourceIdentifierKey]
        guard let idA = try? URL(fileURLWithPath: a.path).resourceValues(forKeys: key).fileResourceIdentifier,
              let idB = try? URL(fileURLWithPath: b.path).resourceValues(forKeys: key).fileResourceIdentifier
        else { return false }
        return idA.isEqual(idB)
    }

    static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == NSFileWriteNoPermissionError || nsError.code == NSFileWriteVolumeReadOnlyError {
            return "Keine Berechtigung, die Datei umzubenennen."
        }
        return nsError.localizedDescription
    }
}
