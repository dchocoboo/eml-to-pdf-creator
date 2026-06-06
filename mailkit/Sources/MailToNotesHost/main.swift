import AppKit
import Foundation
import MailKit

final class EMLDropView: NSView {
    var onDropFiles: (([URL]) -> Void)?

    private let titleLabel = NSTextField(labelWithString: "Drop .eml files here")
    private let detailLabel = NSTextField(labelWithString: "They will be converted using the saved output and Notes folders.")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    var statusText: String {
        get { detailLabel.stringValue }
        set { detailLabel.stringValue = newValue }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        acceptsEMLFiles(sender) ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        acceptsEMLFiles(sender) ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(from: sender).filter { $0.pathExtension.lowercased() == "eml" }
        guard !urls.isEmpty else {
            return false
        }

        onDropFiles?(urls)
        return true
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        registerForDraggedTypes([.fileURL])

        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail

        let stack = NSStackView(views: [titleLabel, detailLabel])
        stack.orientation = .vertical
        stack.spacing = 4
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    private func acceptsEMLFiles(_ sender: NSDraggingInfo) -> Bool {
        fileURLs(from: sender).contains { $0.pathExtension.lowercased() == "eml" }
    }

    private func fileURLs(from sender: NSDraggingInfo) -> [URL] {
        guard let values = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] else {
            return []
        }

        return values
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var keywords = MailToNotesSettings.keywords
    private let keywordInputField = NSTextField()
    private let addKeywordButton = NSButton()
    private let keywordsContainerView = NSView()
    private let keywordsStackView = NSStackView()
    private let notesFolderField = NSTextField()
    private let outputFolderField = NSTextField()
    private let markColorPopup = NSPopUpButton()
    private let dropView = EMLDropView()
    private var queueProcess: Process?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let titleLabel = NSTextField(labelWithString: "MailToNotes")
        titleLabel.font = .boldSystemFont(ofSize: 18)

        let subtitleLabel = NSTextField(labelWithString: "Configure purchase matching for the Mail extension.")
        subtitleLabel.textColor = .secondaryLabelColor

        let keywordsLabel = NSTextField(labelWithString: "Keywords")

        keywordInputField.placeholderString = "Add keyword"
        keywordInputField.target = self
        keywordInputField.action = #selector(addKeywordsFromInput)

        addKeywordButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add keyword")
        addKeywordButton.bezelStyle = .rounded
        addKeywordButton.target = self
        addKeywordButton.action = #selector(addKeywordsFromInput)
        addKeywordButton.toolTip = "Add keyword"

        let keywordInputStack = NSStackView(views: [keywordInputField, addKeywordButton])
        keywordInputStack.orientation = .horizontal
        keywordInputStack.spacing = 8
        keywordInputStack.alignment = .centerY

        keywordsStackView.orientation = .vertical
        keywordsStackView.spacing = 6
        keywordsStackView.alignment = .leading
        keywordsStackView.translatesAutoresizingMaskIntoConstraints = false
        keywordsContainerView.addSubview(keywordsStackView)
        keywordsContainerView.frame = NSRect(x: 0, y: 0, width: 472, height: 160)
        keywordsContainerView.autoresizingMask = [.width]

        let scrollView = NSScrollView()
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.documentView = keywordsContainerView
        renderKeywordRows()

        let notesFolderLabel = NSTextField(labelWithString: "Notes Folder")
        notesFolderField.stringValue = MailToNotesSettings.notesFolder

        let outputFolderLabel = NSTextField(labelWithString: "Output Folder")
        outputFolderField.stringValue = MailToNotesSettings.outputDirectory
        outputFolderField.placeholderString = MailToNotesSettings.defaultOutputDirectory

        let chooseOutputFolderButton = NSButton(
            title: "Choose...",
            target: self,
            action: #selector(chooseOutputFolder)
        )
        chooseOutputFolderButton.bezelStyle = .rounded

        let markColorLabel = NSTextField(labelWithString: "Mail Color")
        markColorPopup.addItems(withTitles: ["green", "blue", "gray", "orange", "purple", "red", "yellow"])
        markColorPopup.selectItem(withTitle: MailToNotesSettings.markColor)

        dropView.onDropFiles = { [weak self] urls in
            self?.convertDroppedEMLFiles(urls)
        }

        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveSettings))
        saveButton.bezelStyle = .rounded

        let reloadButton = NSButton(title: "Reload Visible Messages", target: self, action: #selector(reloadVisibleMessages))
        reloadButton.bezelStyle = .rounded

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 610))
        [
            titleLabel,
            subtitleLabel,
            keywordsLabel,
            keywordInputStack,
            scrollView,
            notesFolderLabel,
            notesFolderField,
            outputFolderLabel,
            outputFolderField,
            chooseOutputFolderButton,
            markColorLabel,
            markColorPopup,
            dropView,
            saveButton,
            reloadButton
        ].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),

            keywordsLabel.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 24),
            keywordsLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),

            keywordInputStack.topAnchor.constraint(equalTo: keywordsLabel.bottomAnchor, constant: 8),
            keywordInputStack.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            keywordInputStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            addKeywordButton.widthAnchor.constraint(equalToConstant: 32),

            scrollView.topAnchor.constraint(equalTo: keywordInputStack.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            scrollView.heightAnchor.constraint(equalToConstant: 150),

            keywordsStackView.topAnchor.constraint(equalTo: keywordsContainerView.topAnchor, constant: 8),
            keywordsStackView.leadingAnchor.constraint(equalTo: keywordsContainerView.leadingAnchor, constant: 8),
            keywordsStackView.trailingAnchor.constraint(equalTo: keywordsContainerView.trailingAnchor, constant: -8),
            keywordsStackView.bottomAnchor.constraint(lessThanOrEqualTo: keywordsContainerView.bottomAnchor, constant: -8),

            notesFolderLabel.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 18),
            notesFolderLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            notesFolderField.centerYAnchor.constraint(equalTo: notesFolderLabel.centerYAnchor),
            notesFolderField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 150),
            notesFolderField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            outputFolderLabel.topAnchor.constraint(equalTo: notesFolderLabel.bottomAnchor, constant: 18),
            outputFolderLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            outputFolderField.centerYAnchor.constraint(equalTo: outputFolderLabel.centerYAnchor),
            outputFolderField.leadingAnchor.constraint(equalTo: notesFolderField.leadingAnchor),
            chooseOutputFolderButton.centerYAnchor.constraint(equalTo: outputFolderField.centerYAnchor),
            chooseOutputFolderButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            outputFolderField.trailingAnchor.constraint(equalTo: chooseOutputFolderButton.leadingAnchor, constant: -8),

            markColorLabel.topAnchor.constraint(equalTo: outputFolderLabel.bottomAnchor, constant: 18),
            markColorLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            markColorPopup.centerYAnchor.constraint(equalTo: markColorLabel.centerYAnchor),
            markColorPopup.leadingAnchor.constraint(equalTo: notesFolderField.leadingAnchor),

            dropView.topAnchor.constraint(equalTo: markColorLabel.bottomAnchor, constant: 18),
            dropView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            dropView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            dropView.heightAnchor.constraint(equalToConstant: 92),

            saveButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            saveButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24),

            reloadButton.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -12),
            reloadButton.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor)
        ])

        let window = NSWindow(
            contentRect: contentView.frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MailToNotes"
        window.contentView = contentView
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window

        NSApp.activate(ignoringOtherApps: true)

        reloadVisibleMessages()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    @objc private func saveSettings() {
        persistSettings(reloadVisibleMessages: true)
    }

    private func persistSettings(reloadVisibleMessages shouldReload: Bool) {
        MailToNotesSettings.save(
            keywords: keywords,
            notesFolder: notesFolderField.stringValue,
            markColor: markColorPopup.titleOfSelectedItem ?? MailToNotesSettings.defaultMarkColor,
            outputDirectory: outputFolderField.stringValue
        )
        if shouldReload {
            reloadVisibleMessages()
        }
    }

    @objc private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Output Folder"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: outputFolderField.stringValue)

        if panel.runModal() == .OK, let url = panel.url {
            outputFolderField.stringValue = url.path
        }
    }

    @objc private func addKeywordsFromInput() {
        let additions = keywordInputField.stringValue
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        guard !additions.isEmpty else {
            keywordInputField.stringValue = ""
            return
        }

        let updatedKeywords = MailToNotesSettings.normalizeKeywords(keywords + additions)
        guard updatedKeywords != keywords else {
            keywordInputField.stringValue = ""
            return
        }

        keywords = updatedKeywords
        keywordInputField.stringValue = ""
        renderKeywordRows()
    }

    @objc private func removeKeyword(_ sender: NSButton) {
        guard keywords.indices.contains(sender.tag) else {
            return
        }

        keywords.remove(at: sender.tag)
        renderKeywordRows()
    }

    @objc private func reloadVisibleMessages() {
        MEExtensionManager.reloadVisibleMessages { error in
            if let error {
                NSLog("MailToNotes reloadVisibleMessages failed: \(error.localizedDescription)")
            }
        }
    }

    private func renderKeywordRows() {
        keywordsStackView.arrangedSubviews.forEach { view in
            keywordsStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let rowCount = max(keywords.count, 1)
        keywordsContainerView.frame.size.height = max(150, CGFloat(rowCount * 30 + 16))

        if keywords.isEmpty {
            let emptyLabel = NSTextField(labelWithString: "No keywords added.")
            emptyLabel.textColor = .secondaryLabelColor
            keywordsStackView.addArrangedSubview(emptyLabel)
            return
        }

        for (index, keyword) in keywords.enumerated() {
            let keywordLabel = NSTextField(labelWithString: keyword)
            keywordLabel.lineBreakMode = .byTruncatingTail
            keywordLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

            let removeButton = NSButton()
            removeButton.image = NSImage(
                systemSymbolName: "minus.circle",
                accessibilityDescription: "Remove \(keyword)"
            )
            removeButton.bezelStyle = .inline
            removeButton.isBordered = false
            removeButton.target = self
            removeButton.action = #selector(removeKeyword(_:))
            removeButton.tag = index
            removeButton.toolTip = "Remove \(keyword)"

            let row = NSStackView(views: [keywordLabel, removeButton])
            row.orientation = .horizontal
            row.spacing = 8
            row.alignment = .centerY
            row.translatesAutoresizingMaskIntoConstraints = false

            keywordsStackView.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: keywordsStackView.widthAnchor).isActive = true
            removeButton.widthAnchor.constraint(equalToConstant: 24).isActive = true
        }
    }

    private func convertDroppedEMLFiles(_ urls: [URL]) {
        guard queueProcess == nil else {
            dropView.statusText = "Conversion is already running."
            return
        }

        persistSettings(reloadVisibleMessages: false)

        do {
            let queuedCount = try queueDroppedFiles(urls)
            guard queuedCount > 0 else {
                dropView.statusText = "Drop one or more .eml files to convert."
                return
            }

            dropView.statusText = "Queued \(queuedCount) file\(queuedCount == 1 ? "" : "s"). Converting..."
            try runQueueProcessor()
        } catch {
            dropView.statusText = "Could not start conversion: \(error.localizedDescription)"
            NSLog("MailToNotes drop conversion failed: \(error.localizedDescription)")
        }
    }

    private func queueDroppedFiles(_ urls: [URL]) throws -> Int {
        let queueDirectory = MailToNotesSettings.applicationSupportDirectory
            .appendingPathComponent("MailToNotes", isDirectory: true)
            .appendingPathComponent("Incoming", isDirectory: true)

        try FileManager.default.createDirectory(
            at: queueDirectory,
            withIntermediateDirectories: true
        )

        var queuedCount = 0
        for sourceURL in urls where sourceURL.pathExtension.lowercased() == "eml" {
            let fileBase = uniqueFileBase(for: sourceURL)
            let emlURL = queueDirectory.appendingPathComponent("\(fileBase).eml")
            let metadataURL = queueDirectory.appendingPathComponent("\(fileBase).json")

            if FileManager.default.fileExists(atPath: emlURL.path) {
                try FileManager.default.removeItem(at: emlURL)
            }

            try FileManager.default.copyItem(at: sourceURL, to: emlURL)

            let metadata = DroppedMessageMetadata(
                subject: sourceURL.deletingPathExtension().lastPathComponent,
                from: "Dropped file",
                dateReceived: nil,
                messageID: nil,
                emlFile: emlURL.lastPathComponent
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(metadata).write(to: metadataURL, options: .atomic)
            queuedCount += 1
        }

        return queuedCount
    }

    private func runQueueProcessor() throws {
        guard let processorURL = processorScriptURL() else {
            throw MailToNotesHostError.processorNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", processorURL.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        process.terminationHandler = { [weak self] process in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            DispatchQueue.main.async {
                self?.queueProcess = nil
                if process.terminationStatus == 0 {
                    self?.dropView.statusText = "Conversion complete."
                } else {
                    self?.dropView.statusText = "Conversion failed. Check Console for details."
                    NSLog("MailToNotes queue processor failed: \(output)")
                }
            }
        }

        queueProcess = process
        try process.run()
    }

    private func processorScriptURL() -> URL? {
        let sourceFileURL = URL(fileURLWithPath: #filePath)
        let mailkitDirectory = sourceFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("process_mailkit_queue.py"),
            Bundle.main.resourceURL?.appendingPathComponent("Scripts/process_mailkit_queue.py"),
            mailkitDirectory.appendingPathComponent("Scripts/process_mailkit_queue.py")
        ].compactMap { $0 }

        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func uniqueFileBase(for sourceURL: URL) -> String {
        let dateStamp = Self.dropDateFormatter.string(from: Date())
        let name = sanitize(sourceURL.deletingPathExtension().lastPathComponent)
        let id = UUID().uuidString.prefix(8)
        return "\(dateStamp)-\(name)-\(id)"
    }

    private func sanitize(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let scalars = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(scalars).replacingOccurrences(
            of: "-+",
            with: "-",
            options: .regularExpression
        )
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String((trimmed.isEmpty ? "dropped-email" : trimmed).prefix(80))
    }

    private static let dropDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

private struct DroppedMessageMetadata: Encodable {
    let subject: String
    let from: String
    let dateReceived: TimeInterval?
    let messageID: String?
    let emlFile: String
}

private enum MailToNotesHostError: LocalizedError {
    case processorNotFound

    var errorDescription: String? {
        switch self {
        case .processorNotFound:
            return "The MailToNotes queue processor script could not be found."
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
