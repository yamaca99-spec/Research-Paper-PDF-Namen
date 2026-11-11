import PaperRenamerCore
import SwiftUI
import UniformTypeIdentifiers

struct EditTarget: Identifiable {
    let id: UUID
}

struct ContentView: View {
    @EnvironmentObject private var controller: RenameController
    @State private var isTargeted = false
    @State private var editTarget: EditTarget?

    var body: some View {
        VStack(spacing: 0) {
            DropZone(isTargeted: isTargeted, compact: !controller.items.isEmpty) {
                controller.choosePDFs()
            }
            .padding(16)

            if !controller.items.isEmpty {
                Divider()
                List {
                    ForEach(controller.items) { item in
                        ItemRow(
                            item: item,
                            onEdit: { editTarget = EditTarget(id: item.id) },
                            onUndo: { controller.undo(id: item.id) },
                            onReveal: { controller.revealInFinder(id: item.id) },
                            onOpen: { controller.open(id: item.id) }
                        )
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))

                Divider()
                HStack {
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Liste leeren") { controller.clearFinished() }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .frame(minWidth: 540, minHeight: 440)
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            loadURLs(from: providers)
            return true
        }
        .sheet(item: $editTarget) { target in
            EditSheet(itemID: target.id)
                .environmentObject(controller)
        }
    }

    private var summary: String {
        let renamed = controller.items.filter { $0.status == .renamed }.count
        let open = controller.items.filter { $0.status == .needsInput || $0.status == .needsReview }.count
        var parts = ["\(renamed) umbenannt"]
        if open > 0 { parts.append("\(open) warten auf dich") }
        return parts.joined(separator: " · ")
    }

    private func loadURLs(from providers: [NSItemProvider]) {
        let fileProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        Task { @MainActor in
            var urls: [URL] = []
            for provider in fileProviders {
                if let url = await Self.loadURL(from: provider) {
                    urls.append(url)
                }
            }
            controller.handle(urls: urls)
        }
    }

    private static func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }
}

// MARK: - Drop zone

struct DropZone: View {
    let isTargeted: Bool
    let compact: Bool
    let onChoose: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isTargeted ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.03))
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.45),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                )

            if compact {
                HStack(spacing: 14) {
                    icon(size: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Weitere PDFs hierher ziehen")
                            .font(.headline)
                        Text("Format: Autor (Jahr) Titel.pdf")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Auswählen…", action: onChoose)
                }
                .padding(.horizontal, 20)
            } else {
                VStack(spacing: 12) {
                    icon(size: 52)
                    Text("PDFs hierher ziehen")
                        .font(.title2.weight(.semibold))
                    Text("Wissenschaftliche Paper werden sofort umbenannt in\n„Autor (Jahr) Titel.pdf“")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button("PDFs auswählen…", action: onChoose)
                        .controlSize(.large)
                        .padding(.top, 4)
                    Text("Tipp: Du kannst PDFs auch auf das App-Symbol im Dock ziehen.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 6)
                }
                .padding(24)
            }
        }
        .frame(height: compact ? 84 : nil)
        .frame(maxHeight: compact ? 84 : .infinity)
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
    }

    private func icon(size: CGFloat) -> some View {
        Image(systemName: "arrow.down.doc")
            .font(.system(size: size, weight: .light))
            .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
    }
}

// MARK: - Row

struct ItemRow: View {
    let item: RenameItem
    let onEdit: () -> Void
    let onUndo: () -> Void
    let onReveal: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            statusIcon
                .frame(width: 22, height: 22)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.currentURL.lastPathComponent)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                    .textSelection(.enabled)
                if item.currentURL != item.originalURL {
                    Text("vorher: \(item.originalURL.lastPathComponent)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }

            Spacer(minLength: 8)

            if !item.isBusy {
                HStack(spacing: 4) {
                    if item.status == .needsInput || item.status == .needsReview {
                        Button("Ergänzen…", action: onEdit)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    } else if case .failed = item.status {
                        EmptyView()
                    } else {
                        iconButton("pencil", help: "Namen bearbeiten", action: onEdit)
                    }
                    iconButton("magnifyingglass", help: "Im Finder zeigen", action: onReveal)
                    iconButton("doc.text", help: "PDF öffnen", action: onOpen)
                    if item.canUndo {
                        iconButton("arrow.uturn.backward", help: "Ursprünglichen Namen wiederherstellen", action: onUndo)
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .contextMenu {
            Button("Namen bearbeiten…", action: onEdit)
            Button("Im Finder zeigen", action: onReveal)
            Button("PDF öffnen", action: onOpen)
            if item.canUndo {
                Divider()
                Button("Rückgängig", action: onUndo)
            }
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch item.status {
        case .analyzing:
            ProgressView().controlSize(.small)
        case .renamed:
            Image(systemName: item.verified ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(item.verified ? Color.green : Color.orange)
                .font(.title3)
        case .alreadyNamed:
            Image(systemName: "checkmark.circle")
                .foregroundStyle(Color.green)
                .font(.title3)
        case .needsReview, .needsInput:
            Image(systemName: "pencil.circle.fill")
                .foregroundStyle(Color.orange)
                .font(.title3)
        case .failed:
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(Color.red)
                .font(.title3)
        case .undone:
            Image(systemName: "arrow.uturn.backward.circle")
                .foregroundStyle(.secondary)
                .font(.title3)
        }
    }

    private var statusText: String {
        switch item.status {
        case .analyzing: return "Wird analysiert…"
        case .renamed: return "Umbenannt · \(item.sourceNote)"
        case .alreadyNamed: return "Hatte bereits den richtigen Namen · \(item.sourceNote)"
        case .needsReview: return "Vorschlag bereit – bitte prüfen und bestätigen"
        case .needsInput: return "Nicht alle Angaben gefunden – bitte ergänzen"
        case .failed(let message): return message
        case .undone: return "Ursprünglicher Name wiederhergestellt"
        }
    }

    private var statusColor: Color {
        switch item.status {
        case .renamed: return item.verified ? .secondary : .orange
        case .needsReview, .needsInput: return .orange
        case .failed: return .red
        default: return .secondary
        }
    }
}
