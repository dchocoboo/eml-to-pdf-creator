import AppKit
import Foundation
import MailKit

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

        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveSettings))
        saveButton.bezelStyle = .rounded

        let reloadButton = NSButton(title: "Reload Visible Messages", target: self, action: #selector(reloadVisibleMessages))
        reloadButton.bezelStyle = .rounded

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 500))
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
        MailToNotesSettings.save(
            keywords: keywords,
            notesFolder: notesFolderField.stringValue,
            markColor: markColorPopup.titleOfSelectedItem ?? MailToNotesSettings.defaultMarkColor,
            outputDirectory: outputFolderField.stringValue
        )
        reloadVisibleMessages()
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
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
