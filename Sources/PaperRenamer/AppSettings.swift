import Foundation
import PaperRenamerCore

enum SettingsKey {
    static let authorStyle = "authorStyle"
    static let separator = "titleSeparator"
    static let onlineLookup = "onlineLookup"
    static let autoRenameUncertain = "autoRenameUncertain"
}

/// User preferences (stored in UserDefaults, edited in the settings window).
struct AppSettings {
    var authorStyle: AuthorStyle
    var separator: TitleSeparator
    var onlineLookup: Bool
    var autoRenameUncertain: Bool

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            SettingsKey.authorStyle: AuthorStyle.apa.rawValue,
            SettingsKey.separator: TitleSeparator.space.rawValue,
            SettingsKey.onlineLookup: true,
            SettingsKey.autoRenameUncertain: true,
        ])
    }

    static var current: AppSettings {
        registerDefaults()
        let defaults = UserDefaults.standard
        return AppSettings(
            authorStyle: AuthorStyle(rawValue: defaults.string(forKey: SettingsKey.authorStyle) ?? "") ?? .apa,
            separator: TitleSeparator(rawValue: defaults.string(forKey: SettingsKey.separator) ?? "") ?? .space,
            onlineLookup: defaults.bool(forKey: SettingsKey.onlineLookup),
            autoRenameUncertain: defaults.bool(forKey: SettingsKey.autoRenameUncertain)
        )
    }

    var formatter: FilenameFormatter {
        FilenameFormatter(authorStyle: authorStyle, separator: separator)
    }
}
