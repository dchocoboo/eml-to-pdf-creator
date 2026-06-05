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

### Apple Mail to Apple Notes

Use `Convert Mail Selection to Notes.applescript` as a macOS Quick Action:

1. Open Automator and create a new **Quick Action**
2. Set **Workflow receives current** to **no input** in **Mail**
3. Add **Run AppleScript**
4. Paste the contents of `Convert Mail Selection to Notes.applescript`
5. Save it as **Convert Mail to Notes**

Then select one or more messages in Apple Mail and run **Mail > Services > Convert Mail to Notes**. The script saves each message as an `.eml`, creates a PDF in `output/`, and creates a note in the `Purchases` folder in Apple Notes.

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
