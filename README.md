# EML to PDF Converter

Convert email `.eml` files to PDF documents.

## Features

- Parses EML files (HTML and plain text emails)
- Handles embedded images (CID attachments)
- Displays email headers (From, To, Cc, Date, Subject)
- Renders to PDF (single page, no breaks)
- Double-click to run on macOS

## Setup

```bash
# Install dependencies
pip3 install -r requirements.txt

# Install Chromium browser
playwright install chromium
```

## Usage

### Apple Mail to PDF

Use `Convert Mail Selection to Notes.applescript` as a macOS Quick Action:

1. Open Automator and create a new **Quick Action**
2. Set **Workflow receives current** to **no input** in **Mail**
3. Add **Run AppleScript**
4. Paste the contents of `Convert Mail Selection to Notes.applescript`
5. Save it as **Convert Mail to PDF**

Then select one or more messages in Apple Mail and run **Mail > Services > Convert Mail to PDF**. The script asks whether to create Apple Notes for that run, defaults to **PDF Only**, saves each message as an `.eml`, and creates a PDF in `output/`. If Notes is enabled and a shortcut named `pdfmail Create Note` or `MailToNotes Create Note` exists, the PDF is sent to that shortcut. Otherwise, the script creates a text-only Apple Note and leaves the PDF in the output folder. After conversion, choose **Open Output Folder** to reveal the PDFs in Finder.

#### Apple Notes Shortcut

Create this once if you want generated PDFs attached to Apple Notes through Shortcuts:

1. Open **Shortcuts** and create a new shortcut.
2. Name it exactly `pdfmail Create Note`. The old name `MailToNotes Create Note` is still supported for existing installs.
3. Add **Create Note** from the Notes actions.
4. Set the action to **Create note with** `Shortcut Input` **in** `Purchases`.
5. Open the action details and set **Name** to the `Shortcut Input` variable.
6. Click the `Shortcut Input` variable in the **Name** field and set **Get** to `Name`.
7. Turn **Open When Run** off.
8. The top receiver block should read **Receive Files from Nowhere**. If it does not, set the shortcut to receive files.
9. Run the app once with Apple Notes enabled. If Shortcuts asks to allow Notes access, choose **Always Allow**.

The finished shortcut should effectively read:

```text
Receive Files from Nowhere
Create note with Shortcut Input in Purchases
  Name: Shortcut Input - Get Name
  Open When Run: off
```

To save a reusable copy, open the shortcut in Shortcuts and choose **File > Export...**. The `shortcuts` command-line tool can run existing shortcuts, but it cannot create or export this shortcut directly.

### MailKit Extension

The `mailkit/` folder contains a MailKit prototype for purchase-like incoming messages. MailKit does not add a custom right-click command for selected messages; it runs as Mail downloads messages. The extension queues matching raw emails, then the processor converts them to PDFs. Apple Notes creation is off by default and can be toggled in `pdfmail.app`; when enabled, the generated PDF is sent to a supported Notes shortcut when present, otherwise a text-only Apple Note is created.

```bash
# Requires the Xcode license to be accepted first.
mailkit/Scripts/build_mailkit_app.sh --install
mailkit/Scripts/process_mailkit_queue.py
```

See `mailkit/README.md` for setup details.

### macOS (Double-click)

1. Put your `.eml` files in the `input/` folder
2. Double-click **"Convert EML Files.command"**
3. Find your PDF files in the `output/` folder

### Command Line

```bash
# Single file
python3 eml_to_image.py input/email.eml -o output/

# Multiple files
python3 eml_to_image.py input/*.eml -o output/

# Custom width
python3 eml_to_image.py input/*.eml -o output/ -w 1024
```

### Options

- `-o, --output` - Output directory (default: same as input file)
- `-w, --width` - Viewport width in pixels (default: 800)

## Folder Structure

```
├── input/           # Put your .eml files here
├── output/          # PDF files will be saved here
├── eml_to_image.py  # Main conversion script
├── Convert EML Files.command  # Double-click to run (macOS)
└── requirements.txt
```
