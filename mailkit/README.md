# MailKit Prototype

This folder contains a MailKit message-action extension prototype for the EML to PDF workflow.

Important limitation: MailKit message action handlers run when Mail downloads messages. They are not a selected-message right-click command API. This prototype watches incoming/downloaded messages, queues purchase-like messages as raw `.eml`, and marks exported messages green.

## Flow

```text
Mail downloads a purchase-like message
-> MailKit extension receives MEMessage
-> extension writes rawData to ~/Library/Containers/com.local.mailtonotes.extension/Data/Library/Application Support/MailToNotes/Incoming
-> process_mailkit_queue.py converts queued .eml files to PDFs
-> process_mailkit_queue.py creates Apple Notes in the Purchases folder
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

After installing, open `/Applications/MailToNotes.app` once, then enable the extension in Mail:

```text
Mail > Settings > Extensions
```

## Configure

Open `MailToNotes.app` to configure how the extension behaves:

- `Keywords`: words matched against the subject and sender.
- `Notes Folder`: Apple Notes folder used by the queue processor.
- `Mail Color`: background color applied to matched messages in Mail.

Click `Save` after changing settings. The app stores settings at:

```text
~/Library/Containers/com.local.mailtonotes.extension/Data/Library/Application Support/MailToNotes/config.json
```

## Process Queued Mail

Run this when messages have been queued:

```bash
mailkit/Scripts/process_mailkit_queue.py
```

The processor reuses `eml_to_image.py`, creates PDFs in `output/`, creates Apple Notes in the configured folder, then removes processed queue files.

## Purchase Matching

By default, the extension matches these words in the subject or sender:

```text
receipt, invoice, order, purchase, payment, booking, reservation, charged
```
