import AppKit
import Darwin
import Foundation

final class EMLDropView: NSView {
    var onDropFiles: (([URL]) -> Void)?
    var onMailMessageDrop: (() -> Bool)?
    var onDebugLog: ((String) -> Void)?

    private let titleLabel = NSTextField(labelWithString: "Drop .eml files here")
    private let detailLabel = NSTextField(labelWithString: "They will be converted using the saved output folder.")
    private lazy var receiver: EMLDropReceiver = {
        let receiver = EMLDropReceiver()
        receiver.onDropFiles = { [weak self] urls in self?.onDropFiles?(urls) }
        receiver.onMailMessageDrop = { [weak self] in self?.onMailMessageDrop?() ?? false }
        receiver.onStatusChange = { [weak self] status in self?.statusText = status }
        receiver.onDebugLog = { [weak self] message in self?.onDebugLog?(message) }
        return receiver
    }()

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
        receiver.accepts(sender) ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        receiver.accepts(sender) ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        receiver.perform(sender)
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        registerForDraggedTypes(EMLDropReceiver.registeredPasteboardTypes)

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

}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTabViewDelegate {
    private var window: NSWindow?
    private var statusItem: NSStatusItem?
    private weak var statusButton: NSStatusBarButton?
    private let statusItemDropView = StatusItemDropView()
    private let statusMenu = NSMenu()
    private let statusMenuStatusItem = NSMenuItem(title: "Ready — drag Mail here", action: nil, keyEquivalent: "")
    private let outputFolderField = NSTextField()
    private let dropView = EMLDropView()
    private let debugTextView = NSTextView()
    private let debugStatusLabel = NSTextField(labelWithString: "Ready")
    private let debugQueueLabel = NSTextField(wrappingLabelWithString: "Queue not loaded.")
    private let mailExportQueue = DispatchQueue(label: "pdfmail Mail export", qos: .userInitiated)
    private var queueProcess: Process?
    private var shouldRunQueueProcessorAgain = false
    private var isMailExportInProgress = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let titleLabel = NSTextField(labelWithString: "pdfmail")
        titleLabel.font = .boldSystemFont(ofSize: 18)

        let subtitleLabel = NSTextField(labelWithString: "Convert Mail messages and dropped .eml files to PDF.")
        subtitleLabel.textColor = .secondaryLabelColor

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

        let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 660, height: 680))
        let tabView = NSTabView(frame: rootView.bounds)
        tabView.delegate = self
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
            outputFolderLabel,
            outputFolderField,
            chooseOutputFolderButton,
            openOutputFolderButton,
            dropView,
            saveButton
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

            outputFolderLabel.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 24),
            outputFolderLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            outputFolderField.centerYAnchor.constraint(equalTo: outputFolderLabel.centerYAnchor),
            outputFolderField.leadingAnchor.constraint(equalTo: settingsView.leadingAnchor, constant: 150),
            chooseOutputFolderButton.centerYAnchor.constraint(equalTo: outputFolderField.centerYAnchor),
            chooseOutputFolderButton.trailingAnchor.constraint(equalTo: settingsView.trailingAnchor, constant: -24),
            openOutputFolderButton.centerYAnchor.constraint(equalTo: outputFolderField.centerYAnchor),
            openOutputFolderButton.trailingAnchor.constraint(equalTo: chooseOutputFolderButton.leadingAnchor, constant: -8),
            outputFolderField.trailingAnchor.constraint(equalTo: openOutputFolderButton.leadingAnchor, constant: -8),

            dropView.topAnchor.constraint(equalTo: outputFolderLabel.bottomAnchor, constant: 18),
            dropView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            dropView.trailingAnchor.constraint(equalTo: settingsView.trailingAnchor, constant: -24),
            dropView.heightAnchor.constraint(equalToConstant: 92),

            saveButton.trailingAnchor.constraint(equalTo: settingsView.trailingAnchor, constant: -24),
            saveButton.bottomAnchor.constraint(equalTo: settingsView.bottomAnchor, constant: -24)
        ])

        let window = NSWindow(
            contentRect: rootView.frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "pdfmail"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = rootView
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window

        NSApp.activate(ignoringOtherApps: true)

        configureStatusItem()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === window else {
            return true
        }

        sender.orderOut(nil)
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
        return false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = item.button else {
            return
        }

        statusItemDropView.translatesAutoresizingMaskIntoConstraints = false
        statusItemDropView.onDropFiles = { [weak self] urls in
            self?.convertDroppedEMLFiles(urls)
        }
        statusItemDropView.onMailMessageDrop = { [weak self] in
            self?.convertSelectedMailMessagesFromDrop() ?? false
        }
        statusItemDropView.onStatusChange = { [weak self] status in
            let state: MenuBarConversionState = status.hasPrefix("Receiving") ? .receiving : .failed
            self?.updateConversionStatus(status, state: state)
        }
        statusItemDropView.onDebugLog = { [weak self] message in
            self?.appendDebugLog(message)
        }
        statusItemDropView.onSymbolChange = { [weak button] symbolName, accessibilityDescription in
            let image = NSImage(
                systemSymbolName: symbolName,
                accessibilityDescription: accessibilityDescription
            )
            image?.isTemplate = true
            button?.image = image
        }
        statusItemDropView.onClick = { [weak button] in
            button?.performClick(nil)
        }

        button.title = "PDF"
        button.imagePosition = .imageLeading
        button.addSubview(statusItemDropView)
        NSLayoutConstraint.activate([
            statusItemDropView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            statusItemDropView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            statusItemDropView.topAnchor.constraint(equalTo: button.topAnchor),
            statusItemDropView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
        ])

        statusMenuStatusItem.isEnabled = false
        statusMenu.addItem(statusMenuStatusItem)
        statusMenu.addItem(.separator())

        let openAppItem = NSMenuItem(
            title: "Open pdfmail…",
            action: #selector(showMainWindow),
            keyEquivalent: ""
        )
        openAppItem.target = self
        statusMenu.addItem(openAppItem)

        let openOutputItem = NSMenuItem(
            title: "Open Output Folder",
            action: #selector(openOutputFolder),
            keyEquivalent: ""
        )
        openOutputItem.target = self
        statusMenu.addItem(openOutputItem)
        statusMenu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit pdfmail",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: ""
        )
        quitItem.target = NSApp
        statusMenu.addItem(quitItem)

        item.menu = statusMenu
        statusItem = item
        statusButton = button
        updateConversionStatus("Ready — drag Mail messages here", state: .idle)
    }

    @objc private func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func updateConversionStatus(_ text: String, state: MenuBarConversionState) {
        dropView.statusText = text
        statusItemDropView.statusText = text
        statusItemDropView.conversionState = state
        statusButton?.toolTip = text
        statusMenuStatusItem.title = shortMenuTitle(text)
    }

    private func shortMenuTitle(_ text: String) -> String {
        guard text.count > 30 else {
            return text
        }
        return String(text.prefix(27)) + "..."
    }

    private func makeDebugView() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 610))

        debugStatusLabel.textColor = .secondaryLabelColor
        debugQueueLabel.textColor = .secondaryLabelColor
        debugQueueLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        debugQueueLabel.maximumNumberOfLines = 4
        debugQueueLabel.lineBreakMode = .byTruncatingTail

        let queueScrollView = NSScrollView()
        queueScrollView.borderType = .bezelBorder
        queueScrollView.hasVerticalScroller = true
        queueScrollView.documentView = debugQueueLabel

        debugTextView.isEditable = false
        debugTextView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        debugTextView.textColor = .labelColor
        debugTextView.backgroundColor = .textBackgroundColor
        debugTextView.string = "Conversion logs will appear here.\n"

        let debugScrollView = NSScrollView()
        debugScrollView.borderType = .bezelBorder
        debugScrollView.hasVerticalScroller = true
        debugScrollView.documentView = debugTextView

        let retryQueueButton = NSButton(
            title: "Retry Queue",
            target: self,
            action: #selector(runQueuedConversionFromDebug)
        )
        retryQueueButton.bezelStyle = .rounded

        let refreshQueueButton = NSButton(
            title: "Refresh Queue",
            target: self,
            action: #selector(refreshQueueFromDebug)
        )
        refreshQueueButton.bezelStyle = .rounded

        let clearQueueButton = NSButton(
            title: "Clear Queue…",
            target: self,
            action: #selector(clearQueueFromDebug)
        )
        clearQueueButton.bezelStyle = .rounded

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

        let buttonStack = NSStackView(views: [retryQueueButton, refreshQueueButton, clearQueueButton, openOutputButton, clearButton])
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 8
        buttonStack.alignment = .centerY

        [debugStatusLabel, queueScrollView, debugScrollView, buttonStack].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        NSLayoutConstraint.activate([
            debugStatusLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            debugStatusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            debugStatusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            queueScrollView.topAnchor.constraint(equalTo: debugStatusLabel.bottomAnchor, constant: 12),
            queueScrollView.leadingAnchor.constraint(equalTo: debugStatusLabel.leadingAnchor),
            queueScrollView.trailingAnchor.constraint(equalTo: debugStatusLabel.trailingAnchor),
            queueScrollView.heightAnchor.constraint(equalToConstant: 86),

            debugScrollView.topAnchor.constraint(equalTo: queueScrollView.bottomAnchor, constant: 12),
            debugScrollView.leadingAnchor.constraint(equalTo: debugStatusLabel.leadingAnchor),
            debugScrollView.trailingAnchor.constraint(equalTo: debugStatusLabel.trailingAnchor),
            debugScrollView.bottomAnchor.constraint(equalTo: buttonStack.topAnchor, constant: -16),

            buttonStack.leadingAnchor.constraint(equalTo: debugStatusLabel.leadingAnchor),
            buttonStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -24)
        ])

        refreshDebugQueue()
        return view
    }

    @objc private func saveSettings() {
        persistSettings()
    }

    @objc private func runQueuedConversionFromDebug() {
        guard queueProcess == nil else {
            debugStatusLabel.stringValue = "Queue processing is already running. Retry is unavailable."
            appendDebugLog("Retry refused because queue processing is already running.")
            return
        }

        guard hasQueuedEMLFiles() else {
            debugStatusLabel.stringValue = "Queue is empty; there is nothing to retry."
            appendDebugLog("Retry requested, but the current pdfmail queue is empty.")
            refreshDebugQueue()
            return
        }

        persistSettings()

        do {
            appendDebugLog("Retrying the current pdfmail queue manually.")
            try runQueueProcessor()
        } catch {
            appendDebugLog("Could not start conversion: \(error.localizedDescription)")
            debugStatusLabel.stringValue = "Could not start conversion."
        }
    }

    @objc private func refreshQueueFromDebug() {
        refreshDebugQueue()
        appendDebugLog("Refreshed the current pdfmail queue.")
    }

    @objc private func clearQueueFromDebug() {
        guard queueProcess == nil else {
            debugStatusLabel.stringValue = "Queue processing is running; clear is unavailable."
            appendDebugLog("Clear queue refused because queue processing is already running.")
            return
        }

        let alert = NSAlert()
        alert.messageText = "Clear Current pdfmail Queue?"
        alert.informativeText = "This permanently removes pending emails, metadata, and temporary artifacts from the current pdfmail Incoming queue. The legacy MailToNotes queue is not affected."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear Queue")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        do {
            let cleared = try withCurrentQueueProcessorLock { queueDirectory in
                var pendingEmails = 0
                var staleArtifacts = 0
                guard FileManager.default.fileExists(atPath: queueDirectory.path) else {
                    return (pendingEmails, staleArtifacts)
                }
                for fileURL in try FileManager.default.contentsOfDirectory(at: queueDirectory, includingPropertiesForKeys: nil) {
                    guard !fileURL.hasDirectoryPath else { continue }
                    if fileURL.pathExtension.lowercased() == "eml" {
                        try FileManager.default.removeItem(at: fileURL)
                        pendingEmails += 1
                    } else if fileURL.lastPathComponent.hasSuffix(".json") || fileURL.lastPathComponent.hasSuffix(".eml.tmp") || fileURL.lastPathComponent.hasSuffix(".json.tmp") {
                        try FileManager.default.removeItem(at: fileURL)
                        staleArtifacts += 1
                    }
                }
                return (pendingEmails, staleArtifacts)
            }
            debugStatusLabel.stringValue = "Cleared \(cleared.0) pending email\(cleared.0 == 1 ? "" : "s") and \(cleared.1) stale artifact\(cleared.1 == 1 ? "" : "s")."
            appendDebugLog(debugStatusLabel.stringValue)
        } catch {
            debugStatusLabel.stringValue = "Could not clear queue."
            appendDebugLog("Could not clear current queue: \(error.localizedDescription)")
        }
        refreshDebugQueue()
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

    private func persistSettings() {
        MailToNotesSettings.save(
            keywords: MailToNotesSettings.defaultKeywords,
            notesFolder: MailToNotesSettings.defaultNotesFolder,
            createAppleNotes: false,
            markColor: MailToNotesSettings.defaultMarkColor,
            outputDirectory: outputFolderField.stringValue
        )
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

    private func convertDroppedEMLFiles(_ urls: [URL]) {
        persistSettings()

        do {
            let queuedCount = try queueDroppedFiles(urls)
            guard queuedCount > 0 else {
                updateConversionStatus("Drop one or more .eml files to convert.", state: .failed)
                return
            }

            appendDebugLog("Queued \(queuedCount) dropped .eml file\(queuedCount == 1 ? "" : "s").")

            guard queueProcess == nil else {
                shouldRunQueueProcessorAgain = true
                updateConversionStatus(
                    "Queued \(queuedCount) more file\(queuedCount == 1 ? "" : "s"). They will convert next.",
                    state: .converting
                )
                debugStatusLabel.stringValue = "Conversion running; more files queued."
                appendDebugLog("Conversion is already running; queued files will be picked up next.")
                return
            }

            updateConversionStatus(
                "Queued \(queuedCount) file\(queuedCount == 1 ? "" : "s"). Converting...",
                state: .converting
            )
            try runQueueProcessor()
        } catch {
            updateConversionStatus("Could not start conversion: \(error.localizedDescription)", state: .failed)
            appendDebugLog("Could not start conversion: \(error.localizedDescription)")
        }
    }

    private func convertSelectedMailMessagesFromDrop() -> Bool {
        guard !isMailExportInProgress else {
            updateConversionStatus("Already receiving selected messages from Mail.", state: .receiving)
            return true
        }

        isMailExportInProgress = true
        updateConversionStatus("Receiving selected messages from Mail...", state: .receiving)
        appendDebugLog("Detected Mail message drop. Exporting selected Mail messages.")

        mailExportQueue.async { [weak self] in
            do {
                let urls = try self?.exportSelectedMailMessages() ?? []
                DispatchQueue.main.async {
                    self?.isMailExportInProgress = false
                    guard !urls.isEmpty else {
                        self?.updateConversionStatus("Mail did not provide any selected messages.", state: .failed)
                        self?.appendDebugLog("Mail selection export returned no messages.")
                        return
                    }

                    self?.convertDroppedEMLFiles(urls)
                }
            } catch {
                DispatchQueue.main.async {
                    self?.isMailExportInProgress = false
                    self?.updateConversionStatus("Could not export Mail selection. Open the Debug tab.", state: .failed)
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
        let queueDirectory = queueDirectoryURLs()[0]

        try FileManager.default.createDirectory(
            at: queueDirectory,
            withIntermediateDirectories: true
        )

        var queuedCount = 0
        for sourceURL in urls where sourceURL.pathExtension.lowercased() == "eml" {
            let fileBase = uniqueFileBase(for: sourceURL)
            let emlURL = queueDirectory.appendingPathComponent("\(fileBase).eml")
            let temporaryEMLURL = queueDirectory.appendingPathComponent("\(fileBase).eml.tmp")
            let metadataURL = queueDirectory.appendingPathComponent("\(fileBase).json")

            let metadata = DroppedMessageMetadata(
                subject: sourceURL.deletingPathExtension().lastPathComponent,
                from: "Dropped file",
                dateReceived: nil,
                messageID: nil,
                emlFile: emlURL.lastPathComponent
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            do {
                try FileManager.default.copyItem(at: sourceURL, to: temporaryEMLURL)
                try encoder.encode(metadata).write(to: metadataURL, options: .atomic)
                try FileManager.default.moveItem(at: temporaryEMLURL, to: emlURL)
            } catch {
                try? FileManager.default.removeItem(at: temporaryEMLURL)
                try? FileManager.default.removeItem(at: metadataURL)
                throw error
            }
            queuedCount += 1
        }

        refreshDebugQueue()
        return queuedCount
    }

    private func hasQueuedEMLFiles() -> Bool {
        let queueDirectory = currentQueueDirectory()
        guard let queuedFiles = try? FileManager.default.contentsOfDirectory(
            at: queueDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return false
        }

        return queuedFiles.contains { $0.pathExtension.lowercased() == "eml" }
    }

    private func currentQueueDirectory() -> URL {
        MailToNotesSettings.applicationSupportDirectory
            .appendingPathComponent(MailToNotesSettings.appSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("Incoming", isDirectory: true)
    }

    private func withCurrentQueueProcessorLock<T>(_ body: (URL) throws -> T) throws -> T {
        let queueDirectory = currentQueueDirectory()
        let supportDirectory = queueDirectory.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        let lockURL = supportDirectory.appendingPathComponent("processor.lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw MailToNotesHostError.queueLockUnavailable
        }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            throw MailToNotesHostError.queueProcessorRunning
        }
        defer { flock(descriptor, LOCK_UN) }
        return try body(queueDirectory)
    }

    private func refreshDebugQueue() {
        let queueDirectory = currentQueueDirectory()
        let files = (try? FileManager.default.contentsOfDirectory(
            at: queueDirectory,
            includingPropertiesForKeys: nil
        ))?.filter { $0.pathExtension.lowercased() == "eml" }.sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
        guard !files.isEmpty else {
            debugQueueLabel.stringValue = "Current pdfmail queue: 0 pending emails"
            return
        }
        let itemLines = files.map { fileURL -> String in
            let metadataURL = fileURL.deletingPathExtension().appendingPathExtension("json")
            let subject: String
            if let data = try? Data(contentsOf: metadataURL),
               let metadata = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let value = metadata["subject"] as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                subject = value
            } else {
                subject = fileURL.deletingPathExtension().lastPathComponent
            }
            return "• \(subject) (\(fileURL.lastPathComponent))"
        }
        debugQueueLabel.stringValue = "Current pdfmail queue: \(files.count) pending email\(files.count == 1 ? "" : "s")\n" + itemLines.joined(separator: "\n")
    }

    private func queueDirectoryURLs() -> [URL] {
        let queueDirectory = currentQueueDirectory()
        let legacyQueueDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Containers", isDirectory: true)
            .appendingPathComponent(MailToNotesSettings.legacyExtensionBundleIdentifier, isDirectory: true)
            .appendingPathComponent("Data", isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent(MailToNotesSettings.legacyAppSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("Incoming", isDirectory: true)
        return [queueDirectory, legacyQueueDirectory]
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
                self.refreshDebugQueue()
                let hasQueuedFollowUp = self.shouldRunQueueProcessorAgain || self.hasQueuedEMLFiles()
                self.shouldRunQueueProcessorAgain = false

                if process.terminationStatus == 0 {
                    self.appendDebugLog("Conversion finished successfully.")

                    if hasQueuedFollowUp {
                        self.updateConversionStatus("Converting newly queued files...", state: .converting)
                        self.debugStatusLabel.stringValue = "Conversion running..."
                        self.appendDebugLog("Starting another conversion pass for files queued during processing.")
                        do {
                            try self.runQueueProcessor()
                        } catch {
                            self.updateConversionStatus(
                                "Could not continue conversion: \(error.localizedDescription)",
                                state: .failed
                            )
                            self.debugStatusLabel.stringValue = "Could not continue conversion."
                            self.appendDebugLog("Could not continue conversion: \(error.localizedDescription)")
                        }
                        return
                    }

                    self.updateConversionStatus("Conversion complete.", state: .succeeded)
                    self.debugStatusLabel.stringValue = "Conversion complete."
                } else {
                    self.updateConversionStatus("Conversion failed. Open the Debug tab.", state: .failed)
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

    func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        if tabViewItem?.identifier as? String == "debug" {
            refreshDebugQueue()
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
    case queueProcessorRunning
    case queueLockUnavailable

    var errorDescription: String? {
        switch self {
        case .processorNotFound:
            return "The pdfmail queue processor script could not be found."
        case .pythonNotFound:
            return "A Python 3 executable could not be found."
        case .mailSelectionExportFailed(let message):
            return message
        case .queueProcessorRunning:
            return "The pdfmail queue processor is running. Retry after it finishes."
        case .queueLockUnavailable:
            return "The pdfmail queue lock could not be opened."
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
