import AppKit
import Foundation
import MailKit

final class EMLDropView: NSView {
    var onDropFiles: (([URL]) -> Void)?
    var onMailMessageDrop: (() -> Bool)?
    var onDebugLog: ((String) -> Void)?

    private let titleLabel = NSTextField(labelWithString: "Drop .eml files here")
    private let detailLabel = NSTextField(labelWithString: "They will be converted using the saved output and Notes folders.")
    private let promiseQueue = OperationQueue()
    private var pendingPromiseReceivers: [NSFilePromiseReceiver] = []

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
        if !urls.isEmpty {
            onDropFiles?(urls)
            return true
        }

        if isMailMessageDrop(sender), onMailMessageDrop?() == true {
            return true
        }

        return receivePromisedFiles(from: sender)
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        let promisedTypes = NSFilePromiseReceiver.readableDraggedTypes
            .map { NSPasteboard.PasteboardType($0) }
        registerForDraggedTypes([.fileURL, NSPasteboard.PasteboardType("NSFilesPromisePboardType")] + promisedTypes)
        promiseQueue.name = "pdfmail promised file receiver"
        promiseQueue.maxConcurrentOperationCount = 1

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
            || isMailMessageDrop(sender)
            || !filePromiseReceivers(from: sender).isEmpty
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

    private func filePromiseReceivers(from sender: NSDraggingInfo) -> [NSFilePromiseReceiver] {
        sender.draggingPasteboard.readObjects(
            forClasses: [NSFilePromiseReceiver.self],
            options: nil
        ) as? [NSFilePromiseReceiver] ?? []
    }

    private func isMailMessageDrop(_ sender: NSDraggingInfo) -> Bool {
        sender.draggingPasteboard.types?.contains {
            $0.rawValue.localizedCaseInsensitiveContains("com.apple.mail")
        } ?? false
    }

    private func receivePromisedFiles(from sender: NSDraggingInfo) -> Bool {
        let receivers = filePromiseReceivers(from: sender)
        guard !receivers.isEmpty else {
            return false
        }

        statusText = "Receiving files from Mail..."
        pendingPromiseReceivers = receivers
        let pasteboardTypes = sender.draggingPasteboard.types?
            .map { $0.rawValue }
            .joined(separator: ", ") ?? "none"
        let promisedTypes = receivers.flatMap { $0.fileTypes }
            .joined(separator: ", ")
        onDebugLog?("Drop pasteboard types: \(pasteboardTypes)")
        onDebugLog?("Mail promised file types: \(promisedTypes)")

        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdfmailDrops-\(UUID().uuidString)", isDirectory: true)

        do {
            try FileManager.default.createDirectory(
                at: destinationURL,
                withIntermediateDirectories: true
            )
        } catch {
            statusText = "Could not prepare drop folder: \(error.localizedDescription)"
            return false
        }

        let group = DispatchGroup()
        let lock = NSLock()
        var receivedURLs: [URL] = []
        var errors: [Error] = []

        for receiver in receivers {
            group.enter()
            receiver.receivePromisedFiles(
                atDestination: destinationURL,
                options: [:],
                operationQueue: promiseQueue
            ) { fileURL, error in
                lock.lock()
                receivedURLs.append(fileURL)
                if let error {
                    errors.append(error)
                }
                lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            let emlURLs = receivedURLs.filter { $0.pathExtension.lowercased() == "eml" }
            let receivedPaths = receivedURLs.map { $0.path }.joined(separator: ", ")
            self?.onDebugLog?("Received promised files: \(receivedPaths)")
            self?.pendingPromiseReceivers = []
            if !emlURLs.isEmpty {
                self?.onDropFiles?(emlURLs)
            } else if let error = errors.first {
                self?.statusText = "Could not receive Mail file: \(error.localizedDescription)"
                self?.onDebugLog?("Promise receive error: \(error.localizedDescription)")
            } else {
                self?.statusText = "Mail did not provide an .eml file."
            }
        }

        return true
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
    private let createAppleNotesButton = NSButton(checkboxWithTitle: "Send PDFs to Apple Notes", target: nil, action: nil)
    private let outputFolderField = NSTextField()
    private let markColorPopup = NSPopUpButton()
    private let dropView = EMLDropView()
    private let debugTextView = NSTextView()
    private let debugStatusLabel = NSTextField(labelWithString: "Ready")
    private let mailExportQueue = DispatchQueue(label: "pdfmail Mail export", qos: .userInitiated)
    private var queueProcess: Process?
    private var shouldRunQueueProcessorAgain = false
    private var isMailExportInProgress = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let titleLabel = NSTextField(labelWithString: "pdfmail")
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

        createAppleNotesButton.state = MailToNotesSettings.createAppleNotes ? .on : .off

        let outputFolderLabel = NSTextField(labelWithString: "Output Folder")
        outputFolderField.stringValue = MailToNotesSettings.outputDirectory
        outputFolderField.placeholderString = MailToNotesSettings.defaultOutputDirectory

        let chooseOutputFolderButton = NSButton(
            title: "Choose...",
            target: self,
            action: #selector(chooseOutputFolder)
        )
        chooseOutputFolderButton.bezelStyle = .rounded

        let openOutputFolderButton = NSButton(
            title: "Open",
            target: self,
            action: #selector(openOutputFolder)
        )
        openOutputFolderButton.bezelStyle = .rounded

        let markColorLabel = NSTextField(labelWithString: "Mail Color")
        markColorPopup.addItems(withTitles: ["green", "blue", "gray", "orange", "purple", "red", "yellow"])
        markColorPopup.selectItem(withTitle: MailToNotesSettings.markColor)

        dropView.onDropFiles = { [weak self] urls in
            self?.convertDroppedEMLFiles(urls)
        }
        dropView.onMailMessageDrop = { [weak self] in
            self?.convertSelectedMailMessagesFromDrop() ?? false
        }
        dropView.onDebugLog = { [weak self] message in
            self?.appendDebugLog(message)
        }

        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveSettings))
        saveButton.bezelStyle = .rounded

        let reloadButton = NSButton(title: "Reload Visible Messages", target: self, action: #selector(reloadVisibleMessages))
        reloadButton.bezelStyle = .rounded

        let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 660, height: 680))
        let tabView = NSTabView(frame: rootView.bounds)
        tabView.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(tabView)

        let settingsView = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 610))
        let settingsTab = NSTabViewItem(identifier: "settings")
        settingsTab.label = "Settings"
        settingsTab.view = settingsView
        tabView.addTabViewItem(settingsTab)

        let debugTab = NSTabViewItem(identifier: "debug")
        debugTab.label = "Debug"
        debugTab.view = makeDebugView()
        tabView.addTabViewItem(debugTab)

        [
            titleLabel,
            subtitleLabel,
            keywordsLabel,
            keywordInputStack,
            scrollView,
            notesFolderLabel,
            notesFolderField,
            createAppleNotesButton,
            outputFolderLabel,
            outputFolderField,
            chooseOutputFolderButton,
            openOutputFolderButton,
            markColorLabel,
            markColorPopup,
            dropView,
            saveButton,
            reloadButton
        ].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            settingsView.addSubview($0)
        }

        NSLayoutConstraint.activate([
            tabView.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 12),
            tabView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 12),
            tabView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -12),
            tabView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -12),

            titleLabel.topAnchor.constraint(equalTo: settingsView.topAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: settingsView.leadingAnchor, constant: 24),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),

            keywordsLabel.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 24),
            keywordsLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),

            keywordInputStack.topAnchor.constraint(equalTo: keywordsLabel.bottomAnchor, constant: 8),
            keywordInputStack.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            keywordInputStack.trailingAnchor.constraint(equalTo: settingsView.trailingAnchor, constant: -24),
            addKeywordButton.widthAnchor.constraint(equalToConstant: 32),

            scrollView.topAnchor.constraint(equalTo: keywordInputStack.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: settingsView.trailingAnchor, constant: -24),
            scrollView.heightAnchor.constraint(equalToConstant: 150),

            keywordsStackView.topAnchor.constraint(equalTo: keywordsContainerView.topAnchor, constant: 8),
            keywordsStackView.leadingAnchor.constraint(equalTo: keywordsContainerView.leadingAnchor, constant: 8),
            keywordsStackView.trailingAnchor.constraint(equalTo: keywordsContainerView.trailingAnchor, constant: -8),
            keywordsStackView.bottomAnchor.constraint(lessThanOrEqualTo: keywordsContainerView.bottomAnchor, constant: -8),

            notesFolderLabel.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 18),
            notesFolderLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            notesFolderField.centerYAnchor.constraint(equalTo: notesFolderLabel.centerYAnchor),
            notesFolderField.leadingAnchor.constraint(equalTo: settingsView.leadingAnchor, constant: 150),
            notesFolderField.trailingAnchor.constraint(equalTo: settingsView.trailingAnchor, constant: -24),

            createAppleNotesButton.topAnchor.constraint(equalTo: notesFolderLabel.bottomAnchor, constant: 14),
            createAppleNotesButton.leadingAnchor.constraint(equalTo: notesFolderField.leadingAnchor),

            outputFolderLabel.topAnchor.constraint(equalTo: createAppleNotesButton.bottomAnchor, constant: 18),
            outputFolderLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            outputFolderField.centerYAnchor.constraint(equalTo: outputFolderLabel.centerYAnchor),
            outputFolderField.leadingAnchor.constraint(equalTo: notesFolderField.leadingAnchor),
            chooseOutputFolderButton.centerYAnchor.constraint(equalTo: outputFolderField.centerYAnchor),
            chooseOutputFolderButton.trailingAnchor.constraint(equalTo: settingsView.trailingAnchor, constant: -24),
            openOutputFolderButton.centerYAnchor.constraint(equalTo: outputFolderField.centerYAnchor),
            openOutputFolderButton.trailingAnchor.constraint(equalTo: chooseOutputFolderButton.leadingAnchor, constant: -8),
            outputFolderField.trailingAnchor.constraint(equalTo: openOutputFolderButton.leadingAnchor, constant: -8),

            markColorLabel.topAnchor.constraint(equalTo: outputFolderLabel.bottomAnchor, constant: 18),
            markColorLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            markColorPopup.centerYAnchor.constraint(equalTo: markColorLabel.centerYAnchor),
            markColorPopup.leadingAnchor.constraint(equalTo: notesFolderField.leadingAnchor),

            dropView.topAnchor.constraint(equalTo: markColorLabel.bottomAnchor, constant: 18),
            dropView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            dropView.trailingAnchor.constraint(equalTo: settingsView.trailingAnchor, constant: -24),
            dropView.heightAnchor.constraint(equalToConstant: 92),

            saveButton.trailingAnchor.constraint(equalTo: settingsView.trailingAnchor, constant: -24),
            saveButton.bottomAnchor.constraint(equalTo: settingsView.bottomAnchor, constant: -24),

            reloadButton.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -12),
            reloadButton.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor)
        ])

        let window = NSWindow(
            contentRect: rootView.frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "pdfmail"
        window.contentView = rootView
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window

        NSApp.activate(ignoringOtherApps: true)

        reloadVisibleMessages()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func makeDebugView() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 610))

        debugStatusLabel.textColor = .secondaryLabelColor

        debugTextView.isEditable = false
        debugTextView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        debugTextView.textColor = .labelColor
        debugTextView.backgroundColor = .textBackgroundColor
        debugTextView.string = "Conversion logs will appear here.\n"

        let debugScrollView = NSScrollView()
        debugScrollView.borderType = .bezelBorder
        debugScrollView.hasVerticalScroller = true
        debugScrollView.documentView = debugTextView

        let runQueuedButton = NSButton(
            title: "Run Queued Conversion",
            target: self,
            action: #selector(runQueuedConversionFromDebug)
        )
        runQueuedButton.bezelStyle = .rounded

        let openOutputButton = NSButton(
            title: "Open Output Folder",
            target: self,
            action: #selector(openOutputFolder)
        )
        openOutputButton.bezelStyle = .rounded

        let clearButton = NSButton(
            title: "Clear Log",
            target: self,
            action: #selector(clearDebugLog)
        )
        clearButton.bezelStyle = .rounded

        let buttonStack = NSStackView(views: [runQueuedButton, openOutputButton, clearButton])
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 8
        buttonStack.alignment = .centerY

        [debugStatusLabel, debugScrollView, buttonStack].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        NSLayoutConstraint.activate([
            debugStatusLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            debugStatusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            debugStatusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            debugScrollView.topAnchor.constraint(equalTo: debugStatusLabel.bottomAnchor, constant: 12),
            debugScrollView.leadingAnchor.constraint(equalTo: debugStatusLabel.leadingAnchor),
            debugScrollView.trailingAnchor.constraint(equalTo: debugStatusLabel.trailingAnchor),
            debugScrollView.bottomAnchor.constraint(equalTo: buttonStack.topAnchor, constant: -16),

            buttonStack.leadingAnchor.constraint(equalTo: debugStatusLabel.leadingAnchor),
            buttonStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -24)
        ])

        return view
    }

    @objc private func saveSettings() {
        persistSettings(reloadVisibleMessages: true)
    }

    @objc private func runQueuedConversionFromDebug() {
        guard queueProcess == nil else {
            appendDebugLog("Conversion is already running.")
            return
        }

        persistSettings(reloadVisibleMessages: false)

        do {
            appendDebugLog("Running queued conversion manually.")
            try runQueueProcessor()
        } catch {
            appendDebugLog("Could not start conversion: \(error.localizedDescription)")
            debugStatusLabel.stringValue = "Could not start conversion."
        }
    }

    @objc private func openOutputFolder() {
        let outputPath = MailToNotesSettings.normalizeOutputDirectory(outputFolderField.stringValue)
        outputFolderField.stringValue = outputPath
        let outputURL = URL(fileURLWithPath: outputPath, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        } catch {
            appendDebugLog("Could not create output folder: \(error.localizedDescription)")
            return
        }
        NSWorkspace.shared.open(outputURL)
    }

    @objc private func clearDebugLog() {
        debugTextView.string = ""
    }

    private func persistSettings(reloadVisibleMessages shouldReload: Bool) {
        MailToNotesSettings.save(
            keywords: keywords,
            notesFolder: notesFolderField.stringValue,
            createAppleNotes: createAppleNotesButton.state == .on,
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
                NSLog("pdfmail reloadVisibleMessages failed: \(error.localizedDescription)")
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
        persistSettings(reloadVisibleMessages: false)

        do {
            let queuedCount = try queueDroppedFiles(urls)
            guard queuedCount > 0 else {
                dropView.statusText = "Drop one or more .eml files to convert."
                return
            }

            appendDebugLog("Queued \(queuedCount) dropped .eml file\(queuedCount == 1 ? "" : "s").")

            guard queueProcess == nil else {
                shouldRunQueueProcessorAgain = true
                dropView.statusText = "Queued \(queuedCount) more file\(queuedCount == 1 ? "" : "s"). They will convert next."
                debugStatusLabel.stringValue = "Conversion running; more files queued."
                appendDebugLog("Conversion is already running; queued files will be picked up next.")
                return
            }

            dropView.statusText = "Queued \(queuedCount) file\(queuedCount == 1 ? "" : "s"). Converting..."
            try runQueueProcessor()
        } catch {
            dropView.statusText = "Could not start conversion: \(error.localizedDescription)"
            appendDebugLog("Could not start conversion: \(error.localizedDescription)")
        }
    }

    private func convertSelectedMailMessagesFromDrop() -> Bool {
        guard !isMailExportInProgress else {
            dropView.statusText = "Already receiving selected messages from Mail."
            return true
        }

        isMailExportInProgress = true
        dropView.statusText = "Receiving selected messages from Mail..."
        appendDebugLog("Detected Mail message drop. Exporting selected Mail messages.")

        mailExportQueue.async { [weak self] in
            do {
                let urls = try self?.exportSelectedMailMessages() ?? []
                DispatchQueue.main.async {
                    self?.isMailExportInProgress = false
                    guard !urls.isEmpty else {
                        self?.dropView.statusText = "Mail did not provide any selected messages."
                        self?.appendDebugLog("Mail selection export returned no messages.")
                        return
                    }

                    self?.convertDroppedEMLFiles(urls)
                }
            } catch {
                DispatchQueue.main.async {
                    self?.isMailExportInProgress = false
                    self?.dropView.statusText = "Could not export Mail selection. Open the Debug tab."
                    self?.appendDebugLog("Could not export Mail selection: \(error.localizedDescription)")
                }
            }
        }

        return true
    }

    private func exportSelectedMailMessages() throws -> [URL] {
        let scriptSource = """
        tell application "Mail"
            set selectedMessages to selection
            set exportedMessages to {}
            repeat with eachMessage in selectedMessages
                set messageSubject to subject of eachMessage
                if messageSubject is missing value then set messageSubject to "Mail message"
                set messageSource to source of eachMessage
                set end of exportedMessages to {messageSubject, messageSource}
            end repeat
            return exportedMessages
        end tell
        """

        guard let script = NSAppleScript(source: scriptSource) else {
            throw MailToNotesHostError.mailSelectionExportFailed("Could not prepare the Mail export script.")
        }

        var scriptError: NSDictionary?
        let result = script.executeAndReturnError(&scriptError)
        if let scriptError {
            throw MailToNotesHostError.mailSelectionExportFailed(appleScriptErrorDescription(scriptError))
        }

        guard result.numberOfItems > 0 else {
            return []
        }

        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdfmailMailDrop-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: exportDirectory,
            withIntermediateDirectories: true
        )

        var urls: [URL] = []
        for index in 1...result.numberOfItems {
            guard let messageDescriptor = result.atIndex(index),
                  let source = messageDescriptor.atIndex(2)?.stringValue,
                  !source.isEmpty else {
                continue
            }

            let subject = messageDescriptor.atIndex(1)?.stringValue ?? "Mail message"
            let emlURL = exportDirectory.appendingPathComponent("\(uniqueFileBase(forSubject: subject)).eml")
            try source.write(to: emlURL, atomically: true, encoding: .utf8)
            urls.append(emlURL)
        }

        return urls
    }

    private func queueDroppedFiles(_ urls: [URL]) throws -> Int {
        let queueDirectory = MailToNotesSettings.applicationSupportDirectory
            .appendingPathComponent(MailToNotesSettings.appSupportDirectoryName, isDirectory: true)
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
        guard let pythonURL = pythonExecutableURL() else {
            throw MailToNotesHostError.pythonNotFound
        }

        let process = Process()
        process.executableURL = pythonURL
        process.arguments = [processorURL.path]
        process.environment = [
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "PATH": "/opt/homebrew/opt/python@3.14/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        ]

        debugStatusLabel.stringValue = "Conversion running..."
        appendDebugLog("Using Python: \(pythonURL.path)")
        appendDebugLog("Using processor: \(processorURL.path)")

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else {
                return
            }

            DispatchQueue.main.async {
                self?.appendDebugLog(output, includeTimestamp: false)
            }
        }

        process.terminationHandler = { [weak self] process in
            pipe.fileHandleForReading.readabilityHandler = nil

            DispatchQueue.main.async {
                guard let self else {
                    return
                }

                self.queueProcess = nil
                let hasQueuedFollowUp = self.shouldRunQueueProcessorAgain
                self.shouldRunQueueProcessorAgain = false

                if process.terminationStatus == 0 {
                    self.appendDebugLog("Conversion finished successfully.")

                    if hasQueuedFollowUp {
                        self.dropView.statusText = "Converting newly queued files..."
                        self.debugStatusLabel.stringValue = "Conversion running..."
                        self.appendDebugLog("Starting another conversion pass for files queued during processing.")
                        do {
                            try self.runQueueProcessor()
                        } catch {
                            self.dropView.statusText = "Could not continue conversion: \(error.localizedDescription)"
                            self.debugStatusLabel.stringValue = "Could not continue conversion."
                            self.appendDebugLog("Could not continue conversion: \(error.localizedDescription)")
                        }
                        return
                    }

                    self.dropView.statusText = "Conversion complete."
                    self.debugStatusLabel.stringValue = "Conversion complete."
                } else {
                    self.dropView.statusText = "Conversion failed. Open the Debug tab."
                    self.debugStatusLabel.stringValue = "Conversion failed."
                    self.appendDebugLog("Conversion failed with exit code \(process.terminationStatus).")
                    if hasQueuedFollowUp {
                        self.appendDebugLog("Files queued during the failed conversion remain in the queue.")
                    }
                }
            }
        }

        queueProcess = process
        do {
            try process.run()
        } catch {
            queueProcess = nil
            pipe.fileHandleForReading.readabilityHandler = nil
            throw error
        }
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

    private func pythonExecutableURL() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "/opt/homebrew/opt/python@3.14/bin/python3.14",
            "/opt/homebrew/bin/python3",
            "\(home)/.pyenv/shims/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3"
        ]

        return candidates
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private func appendDebugLog(_ message: String, includeTimestamp: Bool = true) {
        let prefix = includeTimestamp ? "[\(Self.debugDateFormatter.string(from: Date()))] " : ""
        let text = message.hasSuffix("\n") ? "\(prefix)\(message)" : "\(prefix)\(message)\n"
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .foregroundColor: NSColor.labelColor,
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            ]
        )
        debugTextView.textStorage?.append(attributed)
        debugTextView.scrollRangeToVisible(NSRange(location: debugTextView.string.count, length: 0))
    }

    private func uniqueFileBase(for sourceURL: URL) -> String {
        let dateStamp = Self.dropDateFormatter.string(from: Date())
        let name = sanitize(sourceURL.deletingPathExtension().lastPathComponent)
        let id = UUID().uuidString.prefix(8)
        return "\(dateStamp)-\(name)-\(id)"
    }

    private func uniqueFileBase(forSubject subject: String) -> String {
        let dateStamp = Self.dropDateFormatter.string(from: Date())
        let name = sanitize(subject)
        let id = UUID().uuidString.prefix(8)
        return "\(dateStamp)-\(name)-\(id)"
    }

    private func appleScriptErrorDescription(_ error: NSDictionary) -> String {
        if let message = error[NSAppleScript.errorMessage] as? String {
            return message
        }

        if let number = error[NSAppleScript.errorNumber] {
            return "AppleScript failed with error \(number)."
        }

        return "AppleScript failed while reading the selected Mail messages."
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

    private static let debugDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
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
    case pythonNotFound
    case mailSelectionExportFailed(String)

    var errorDescription: String? {
        switch self {
        case .processorNotFound:
            return "The pdfmail queue processor script could not be found."
        case .pythonNotFound:
            return "A Python 3 executable could not be found."
        case .mailSelectionExportFailed(let message):
            return message
        }
    }
}

private func configureMainMenu() {
    let mainMenu = NSMenu()
    let appMenuItem = NSMenuItem()
    mainMenu.addItem(appMenuItem)

    let appMenu = NSMenu()
    let quitTitle = "Quit \(ProcessInfo.processInfo.processName)"
    appMenu.addItem(
        NSMenuItem(
            title: quitTitle,
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
    )
    appMenuItem.submenu = appMenu
    NSApp.mainMenu = mainMenu
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
configureMainMenu()
app.run()
