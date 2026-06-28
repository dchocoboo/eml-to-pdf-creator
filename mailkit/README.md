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

## Process Queued Mail

Run this when messages have been queued:

```bash
mailkit/Scripts/process_mailkit_queue.py
```

The processor reuses `eml_to_image.py`, creates PDFs in the configured output folder, optionally sends PDFs to the `pdfmail Create Note` shortcut, then removes processed queue files. If neither supported shortcut exists, it creates text-only Apple Notes instead. See the main README's **Apple Notes Shortcut** section for the exact Shortcuts setup and export instructions.

## Purchase Matching

By default, the extension matches these words in the subject or sender:

```text
receipt, invoice, order, purchase, payment, booking, reservation, charged
```
