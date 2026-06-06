import Foundation

enum MailToNotesSettings {
    static let defaultKeywords = [
        "receipt",
        "invoice",
        "order",
        "purchase",
        "payment",
        "booking",
        "reservation",
        "charged"
    ]
    static let defaultNotesFolder = "Purchases"
    static let defaultMarkColor = "green"

    struct Config: Codable {
        var keywords: [String]
        var notesFolder: String
        var markColor: String
    }

    static var configURL: URL {
        applicationSupportDirectory
            .appendingPathComponent("MailToNotes", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    static var applicationSupportDirectory: URL {
        if Bundle.main.bundleIdentifier == "com.local.mailtonotes" {
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Containers", isDirectory: true)
                .appendingPathComponent("com.local.mailtonotes.extension", isDirectory: true)
                .appendingPathComponent("Data", isDirectory: true)
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
        }

        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return appSupport
    }

    static var keywords: [String] {
        load().keywords
    }

    static var notesFolder: String {
        load().notesFolder
    }

    static var markColor: String {
        load().markColor
    }

    static func save(keywords: [String], notesFolder: String, markColor: String) {
        let config = Config(
            keywords: normalizeKeywords(keywords),
            notesFolder: normalizeNotesFolder(notesFolder),
            markColor: normalizeMarkColor(markColor)
        )

        do {
            try FileManager.default.createDirectory(
                at: configURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(config)
            try data.write(to: configURL, options: .atomic)
        } catch {
            NSLog("MailToNotes failed to save settings: \(error.localizedDescription)")
        }
    }

    static func load() -> Config {
        do {
            let data = try Data(contentsOf: configURL)
            let config = try JSONDecoder().decode(Config.self, from: data)
            return Config(
                keywords: normalizeKeywords(config.keywords),
                notesFolder: normalizeNotesFolder(config.notesFolder),
                markColor: normalizeMarkColor(config.markColor)
            )
        } catch {
            return Config(
                keywords: defaultKeywords,
                notesFolder: defaultNotesFolder,
                markColor: defaultMarkColor
            )
        }
    }

    static func normalizeKeywords(_ rawKeywords: [String]) -> [String] {
        let keywords = rawKeywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        return keywords.isEmpty ? defaultKeywords : Array(Set(keywords)).sorted()
    }

    static func normalizeNotesFolder(_ notesFolder: String) -> String {
        let trimmed = notesFolder.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultNotesFolder : trimmed
    }

    static func normalizeMarkColor(_ markColor: String) -> String {
        let allowedColors = ["green", "blue", "gray", "orange", "purple", "red", "yellow"]
        return allowedColors.contains(markColor) ? markColor : defaultMarkColor
    }
}
