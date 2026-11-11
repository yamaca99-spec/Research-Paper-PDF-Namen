import PaperRenamerCore
import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKey.authorStyle) private var authorStyle: AuthorStyle = .apa
    @AppStorage(SettingsKey.separator) private var separator: TitleSeparator = .space
    @AppStorage(SettingsKey.onlineLookup) private var onlineLookup = true
    @AppStorage(SettingsKey.autoRenameUncertain) private var autoRenameUncertain = true

    private var example: String {
        let formatter = FilenameFormatter(authorStyle: authorStyle, separator: separator)
        let authors = [Author(family: "Müller"), Author(family: "Schmidt"), Author(family: "Weber")]
        let author = formatter.authorText(authors) ?? "Müller"
        return (formatter.baseName(author: author, year: "2021", title: "Titel des Papers") ?? "") + ".pdf"
    }

    var body: some View {
        Form {
            Section {
                Picker("Autoren:", selection: $authorStyle) {
                    ForEach(AuthorStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                Picker("Format:", selection: $separator) {
                    ForEach(TitleSeparator.allCases) { separator in
                        Text(separator.label).tag(separator)
                    }
                }
                LabeledContent("Beispiel:") {
                    Text(example)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Divider()
                .padding(.vertical, 6)

            Section {
                Toggle("Metadaten online nachschlagen (Crossref, doi.org, arXiv)", isOn: $onlineLookup)
                Text("Gesendet werden nur DOI, arXiv-Nummer oder Titel – niemals die PDF selbst. Ohne Internet wird der Name nur aus der PDF geschätzt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Auch unsichere Ergebnisse sofort umbenennen", isOn: $autoRenameUncertain)
                Text("Wenn aus: Namen, die nicht online bestätigt wurden, musst du erst bestätigen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
        .frame(width: 500)
    }
}
