#!/bin/bash
# Double-click this file in Finder to convert all .eml files in the input folder

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Use the actual Python executable (not the pyenv shim)
# Pass the absolute path so it works from any directory (including when called from Shortcuts)
/opt/homebrew/opt/python@3.14/bin/python3.14 "$SCRIPT_DIR/convert_emails.py"
