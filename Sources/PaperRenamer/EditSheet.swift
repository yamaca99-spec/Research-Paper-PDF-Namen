import PaperRenamerCore
import SwiftUI

/// Lets the user correct or complete author, year and title before renaming.
struct EditSheet: View {
    let itemID: UUID

    @EnvironmentObject private var controller: RenameController
    @Environment(\.dismiss) private var dismiss

    @State private var author = ""
    @State private var year = ""
    @State private var title = ""
    @State private var loaded = false

    private var previewName: String? {
        AppSettings.current.formatter.baseName(author: author, year: year, title: title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Dateinamen bearbeiten")
                .font(.headline)

            if let item = controller.item(id: itemID) {
                Text(item.currentURL.lastPathComponent)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Form {
                TextField("Autor:", text: $author, prompt: Text("z. B. Müller et al."))
                TextField("Jahr:", text: $year, prompt: Text("z. B. 2021"))
                TextField("Titel:", text: $title, prompt: Text("Titel des Papers"), axis: .vertical)
                    .lineLimit(2...5)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Neuer Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(previewName.map { $0 + ".pdf" } ?? "Bitte Autor, Jahr und Titel ausfüllen")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(previewName == nil ? Color.orange : Color.primary)
                    .textSelection(.enabled)
            }

            HStack {
                Spacer()
                Button("Abbrechen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Umbenennen") {
                    controller.applyEdit(id: itemID, author: author, year: year, title: title)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(previewName == nil)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear {
            guard !loaded, let item = controller.item(id: itemID) else { return }
            author = item.authorText
            year = item.yearText
            title = item.titleText
            loaded = true
        }
    }
}
