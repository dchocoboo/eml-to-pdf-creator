# MailKit Prototype

This folder contains a MailKit message-action extension prototype for the EML to PDF workflow.

Important limitation: MailKit message action handlers run when Mail downloads messages. They are not a selected-message right-click command API. This prototype watches incoming/downloaded messages, queues purchase-like messages as raw `.eml`, and marks exported messages green.

## Flow

```text
Mail downloads a purchase-like message
-> MailKit extension receives MEMessage
-> extension writes rawData to ~/Library/Containers/com.local.pdfmail.extension/Data/Library/Application Support/pdfmail/Incoming
-> process_mailkit_queue.py converts queued .eml files to PDFs
-> Apple Notes creation runs only when enabled in pdfmail.app
```

## Build

Xcode is required because MailKit is an Apple SDK framework. If Xcode has not been used on this Mac yet, accept the license first:

```bash
sudo xcodebuild -license
```

Then build and install the containing app:

```bash
mailkit/Scripts/build_mailkit_app.sh --install
```

After installing, open `/Applications/pdfmail.app` once, then enable the extension in Mail:

```text
Mail > Settings > Extensions
```

## Configure

Open `pdfmail.app` to configure how the extension behaves:

- `Keywords`: words matched against the subject and sender.
- `Notes Folder`: Apple Notes destination when `Send PDFs to Apple Notes` is enabled.
- `Send PDFs to Apple Notes`: off by default. When a shortcut named `pdfmail Create Note` or `MailToNotes Create Note` exists, PDFs are sent to that shortcut; otherwise notes are created without PDF attachments.
- `Output Folder`: where PDFs are written. Use `Open` to reveal it in Finder.
- `Mail Color`: background color applied to matched messages in Mail.

Click `Save` after changing settings. The app stores settings at:

```text
~/Library/Containers/com.local.pdfmail.extension/Data/Library/Application Support/pdfmail/config.json
```

## Menu Bar Drop

While `pdfmail.app` is running, an envelope icon appears in the macOS menu bar.
Drag one or more messages from Apple Mail's message list directly onto that icon
to convert them using the saved output and Apple Notes settings. The icon changes
while pdfmail receives and converts the messages, then shows success or failure.

Click the icon to open pdfmail, reveal the output folder, or quit. Closing the
settings window leaves pdfmail running so the drop target remains available,
but removes the app from the Dock until the settings window is reopened.
The first direct Mail drop may prompt for permission to control Apple Mail.

## Programmatic Access / MCP

Use the automation script directly when another local workflow already knows
the `.eml` file path:

```bash
mailkit/Scripts/pdfmail_automation.py status
mailkit/Scripts/pdfmail_automation.py settings
mailkit/Scripts/pdfmail_automation.py convert /absolute/path/to/message.eml
mailkit/Scripts/pdfmail_automation.py process-queue
```

All CLI responses are JSON. `convert` uses the same current queue, saved output
folder, and Apple Notes setting as the app. A process lock serializes app, CLI,
and MCP conversions.

To connect an MCP client to the installed app's local stdio server:

```json
{
  "mcpServers": {
    "pdfmail": {
      "command": "/opt/homebrew/bin/python3",
      "args": [
        "/Applications/pdfmail.app/Contents/Resources/pdfmail_automation.py",
        "mcp"
      ]
    }
  }
}
```

Available tools are `convert_eml`, `get_status`, `get_settings`, and
`process_queue`. The server has no network listener; the MCP client launches it
locally and communicates over stdio. It never processes the legacy queue unless
that separate migration is run explicitly.

## Process Queued Mail

Run this when messages have been queued:

```bash
mailkit/Scripts/process_mailkit_queue.py
```

The normal command processes only the current `pdfmail` queue. To deliberately
process the historical `MailToNotes` queue as a one-time migration, use
`mailkit/Scripts/process_mailkit_queue.py --include-legacy`.

The processor reuses `eml_to_image.py`, creates PDFs in the configured output folder, optionally sends PDFs to the `pdfmail Create Note` shortcut, then removes processed queue files. If neither supported shortcut exists, it creates text-only Apple Notes instead. See the main README's **Apple Notes Shortcut** section for the exact Shortcuts setup and export instructions.

## Purchase Matching

By default, the extension matches these words in the subject or sender:

```text
receipt, invoice, order, purchase, payment, booking, reservation, charged
```
