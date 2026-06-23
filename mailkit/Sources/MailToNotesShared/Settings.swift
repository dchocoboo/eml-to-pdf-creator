import Foundation

enum MailToNotesSettings {
    static let hostBundleIdentifier = "com.local.mailtonotes"
    static let extensionBundleIdentifier = "com.local.mailtonotes.extension"
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
    static let defaultCreateAppleNotes = false
    static let defaultMarkColor = "green"
    static let defaultOutputDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Documents", isDirectory: true)
        .appendingPathComponent("MailToNotes PDFs", isDirectory: true)
        .path

    struct Config: Codable {
        var keywords: [String]
        var notesFolder: String
        var createAppleNotes: Bool?
        var markColor: String
        var outputDirectory: String?
    }

    static var preferencesURL: URL {
        sharedLibraryDirectory
            .appendingPathComponent("Preferences", isDirectory: true)
            .appendingPathComponent("com.local.mailtonotes.settings.plist")
    }

    static var configURL: URL {
        applicationSupportDirectory
            .appendingPathComponent("MailToNotes", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    static var sharedLibraryDirectory: URL {
        if Bundle.main.bundleIdentifier == extensionBundleIdentifier {
            return FileManager.default.urls(
                for: .libraryDirectory,
                in: .userDomainMask
            )[0]
        }

        return containerLibraryDirectory(for: extensionBundleIdentifier)
    }

    static var applicationSupportDirectory: URL {
        let appSupport = sharedLibraryDirectory
            .appendingPathComponent("Application Support", isDirectory: true)
        return appSupport
    }

    static var keywords: [String] {
        load().keywords
    }

    static var notesFolder: String {
        load().notesFolder
    }

    static var createAppleNotes: Bool {
        load().createAppleNotes ?? defaultCreateAppleNotes
    }

    static var markColor: String {
        load().markColor
    }

    static var outputDirectory: String {
        normalizeOutputDirectory(load().outputDirectory)
    }

    static func save(
        keywords: [String],
        notesFolder: String,
        createAppleNotes: Bool,
        markColor: String,
        outputDirectory: String
    ) {
        let config = Config(
            keywords: normalizeKeywords(keywords),
            notesFolder: normalizeNotesFolder(notesFolder),
            createAppleNotes: createAppleNotes,
            markColor: normalizeMarkColor(markColor),
            outputDirectory: normalizeOutputDirectory(outputDirectory)
        )

        do {
            try FileManager.default.createDirectory(
                at: preferencesURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            let data = try encoder.encode(config)
            try data.write(to: preferencesURL, options: .atomic)
        } catch {
            NSLog("MailToNotes failed to save settings: \(error.localizedDescription)")
        }
    }

    static func load() -> Config {
        if let preferencesConfig = loadPreferencesConfig() {
            return preferencesConfig
        }

        if let legacyConfig = loadLegacyConfig() {
            save(
                keywords: legacyConfig.keywords,
                notesFolder: legacyConfig.notesFolder,
                createAppleNotes: legacyConfig.createAppleNotes ?? defaultCreateAppleNotes,
                markColor: legacyConfig.markColor,
                outputDirectory: normalizeOutputDirectory(legacyConfig.outputDirectory)
            )
            return legacyConfig
        }

        return Config(
            keywords: defaultKeywords,
            notesFolder: defaultNotesFolder,
            createAppleNotes: defaultCreateAppleNotes,
            markColor: defaultMarkColor,
            outputDirectory: defaultOutputDirectory
        )
    }

    private static func loadPreferencesConfig() -> Config? {
        for url in candidatePreferencesURLs {
            do {
                let data = try Data(contentsOf: url)
                let config = try PropertyListDecoder().decode(Config.self, from: data)
                return normalizedConfig(config)
            } catch {
                continue
            }
        }
        return nil
    }

    private static func loadLegacyConfig() -> Config? {
        for url in candidateConfigURLs {
            do {
                let data = try Data(contentsOf: url)
                let config = try JSONDecoder().decode(Config.self, from: data)
                return normalizedConfig(config)
            } catch {
                continue
            }
        }
        return nil
    }

    private static func normalizedConfig(_ config: Config) -> Config {
        Config(
            keywords: normalizeKeywords(config.keywords),
            notesFolder: normalizeNotesFolder(config.notesFolder),
            createAppleNotes: config.createAppleNotes ?? defaultCreateAppleNotes,
            markColor: normalizeMarkColor(config.markColor),
            outputDirectory: normalizeOutputDirectory(config.outputDirectory)
        )
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

    static func normalizeOutputDirectory(_ outputDirectory: String?) -> String {
        let trimmed = outputDirectory?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? defaultOutputDirectory : (trimmed as NSString).expandingTildeInPath
    }

    private static var candidatePreferencesURLs: [URL] {
        uniqueURLs([
            preferencesURL,
            preferencesURL(in: containerLibraryDirectory(for: hostBundleIdentifier))
        ])
    }

    private static var candidateConfigURLs: [URL] {
        uniqueURLs([
            configURL,
            configURL(in: containerLibraryDirectory(for: hostBundleIdentifier))
        ])
    }

    private static func preferencesURL(in libraryDirectory: URL) -> URL {
        libraryDirectory
            .appendingPathComponent("Preferences", isDirectory: true)
            .appendingPathComponent("com.local.mailtonotes.settings.plist")
    }

    private static func configURL(in libraryDirectory: URL) -> URL {
        libraryDirectory
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("MailToNotes", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    private static func containerLibraryDirectory(for bundleIdentifier: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Containers", isDirectory: true)
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("Data", isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
    }

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { url in
            seen.insert(url.standardizedFileURL.path).inserted
        }
    }
}
