# EML to PDF/PNG Converter

Convert email `.eml` files to PNG images and PDF documents.

## Features

- Parses EML files (HTML and plain text emails)
- Handles embedded images (CID attachments)
- Displays email headers (From, To, Cc, Date, Subject)
- Renders to high-quality PNG (2x retina scale) and PDF (single page, no breaks)
- Double-click to run on macOS

## Setup

```bash
# Create virtual environment
python3 -m venv .venv

# Install dependencies
.venv/bin/pip install playwright

# Install Chromium browser
.venv/bin/playwright install chromium
```

## Usage

### macOS (Double-click)

1. Put your `.eml` files in the `input/` folder
2. Double-click **"Convert EML Files.command"**
3. Find your PNG and PDF files in the `output/` folder

### Command Line

```bash
# Single file
.venv/bin/python eml_to_image.py input/email.eml -o output/

# Multiple files
.venv/bin/python eml_to_image.py input/*.eml -o output/

# Custom width and scale
.venv/bin/python eml_to_image.py input/*.eml -o output/ -w 1024 -s 3.0
```

### Options

- `-o, --output` - Output directory (default: same as input file)
- `-w, --width` - Viewport width in pixels (default: 800)
- `-s, --scale` - Device scale factor for PNG quality (default: 2.0 for retina)

## Folder Structure

```
├── input/           # Put your .eml files here
├── output/          # PNG and PDF files will be saved here
├── eml_to_image.py  # Main conversion script
├── Convert EML Files.command  # Double-click to run (macOS)
└── requirements.txt
```
