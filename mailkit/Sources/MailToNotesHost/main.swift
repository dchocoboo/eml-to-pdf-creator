import AppKit
import Foundation
import MailKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private let keywordsField = NSTextView()
    private let notesFolderField = NSTextField()
    private let markColorPopup = NSPopUpButton()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let titleLabel = NSTextField(labelWithString: "MailToNotes")
        titleLabel.font = .boldSystemFont(ofSize: 18)

        let subtitleLabel = NSTextField(labelWithString: "Configure purchase matching for the Mail extension.")
        subtitleLabel.textColor = .secondaryLabelColor

        let keywordsLabel = NSTextField(labelWithString: "Keywords")
        keywordsField.string = MailToNotesSettings.keywords.joined(separator: "\n")
        keywordsField.font = .monospacedSystemFont(ofSize: 13, weight: .regular)

        let scrollView = NSScrollView()
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.documentView = keywordsField

        let notesFolderLabel = NSTextField(labelWithString: "Notes Folder")
        notesFolderField.stringValue = MailToNotesSettings.notesFolder

        let markColorLabel = NSTextField(labelWithString: "Mail Color")
        markColorPopup.addItems(withTitles: ["green", "blue", "gray", "orange", "purple", "red", "yellow"])
        markColorPopup.selectItem(withTitle: MailToNotesSettings.markColor)

        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveSettings))
        saveButton.bezelStyle = .rounded

        let reloadButton = NSButton(title: "Reload Visible Messages", target: self, action: #selector(reloadVisibleMessages))
        reloadButton.bezelStyle = .rounded

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 420))
        [
            titleLabel,
            subtitleLabel,
            keywordsLabel,
            scrollView,
            notesFolderLabel,
            notesFolderField,
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

            scrollView.topAnchor.constraint(equalTo: keywordsLabel.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            scrollView.heightAnchor.constraint(equalToConstant: 170),

            notesFolderLabel.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 18),
            notesFolderLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            notesFolderField.centerYAnchor.constraint(equalTo: notesFolderLabel.centerYAnchor),
            notesFolderField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 150),
            notesFolderField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            markColorLabel.topAnchor.constraint(equalTo: notesFolderLabel.bottomAnchor, constant: 18),
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

    @objc private func saveSettings() {
        let keywords = keywordsField.string
            .components(separatedBy: .newlines)
            .flatMap { $0.components(separatedBy: ",") }
        MailToNotesSettings.save(
            keywords: keywords,
            notesFolder: notesFolderField.stringValue,
            markColor: markColorPopup.titleOfSelectedItem ?? MailToNotesSettings.defaultMarkColor
        )
        reloadVisibleMessages()
    }

    @objc private func reloadVisibleMessages() {
        MEExtensionManager.reloadVisibleMessages { error in
            if let error {
                NSLog("MailToNotes reloadVisibleMessages failed: \(error.localizedDescription)")
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
