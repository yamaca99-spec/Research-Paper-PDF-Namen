import AppKit
import SwiftUI

struct PaperRenamerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var controller = RenameController.shared

    init() {
        AppSettings.registerDefaults()
    }

    var body: some Scene {
        Window("Paper Renamer", id: "main") {
            ContentView()
                .environmentObject(controller)
        }
        .defaultSize(width: 620, height: 560)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("PDFs auswählen…") {
                    controller.choosePDFs()
                }
                .keyboardShortcut("o")
            }
        }

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// PDFs dropped on the Dock icon or opened via "Öffnen mit".
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            RenameController.shared.handle(urls: urls)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
