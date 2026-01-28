#!/bin/bash
# Double-click this file in Finder to convert all .eml files in the input folder

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INPUT_DIR="$SCRIPT_DIR/input"
OUTPUT_DIR="$SCRIPT_DIR/output"

# Change to the script directory
cd "$SCRIPT_DIR"

echo "============================================"
echo "EML to PNG/PDF Converter"
echo "============================================"
echo ""
echo "Input folder:  $INPUT_DIR"
echo "Output folder: $OUTPUT_DIR"
echo ""

# Create folders if they don't exist
mkdir -p "$INPUT_DIR" "$OUTPUT_DIR"

# Check if virtual environment exists
if [ ! -d "$SCRIPT_DIR/.venv" ]; then
    echo "Error: Virtual environment not found at $SCRIPT_DIR/.venv"
    echo "Please run: python3 -m venv .venv && .venv/bin/pip install playwright && .venv/bin/playwright install chromium"
    echo ""
    read -p "Press Enter to close..."
    exit 1
fi

# Find all .eml files in input folder
EML_FILES=$(find "$INPUT_DIR" -maxdepth 1 -name "*.eml" -type f)

if [ -z "$EML_FILES" ]; then
    echo "No .eml files found in input folder."
    echo "Please put your .eml files in: $INPUT_DIR"
    echo ""
    read -p "Press Enter to close..."
    exit 0
fi

echo "Found the following .eml files:"
find "$INPUT_DIR" -maxdepth 1 -name "*.eml" -type f | while read -r file; do
    echo "  - $(basename "$file")"
done
echo ""

# Convert each .eml file
echo "Starting conversion..."
echo ""

"$SCRIPT_DIR/.venv/bin/python" "$SCRIPT_DIR/eml_to_image.py" "$INPUT_DIR"/*.eml -o "$OUTPUT_DIR"

echo ""
echo "============================================"
echo "Conversion complete!"
echo "Output files are in: $OUTPUT_DIR"
echo "============================================"
echo ""
read -p "Press Enter to close..."
