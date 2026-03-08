#!/bin/bash
# Double-click this file in Finder to convert all .eml files in the input folder

cd "$(dirname "$0")"

# Use the actual Python executable (not the pyenv shim)
# This ensures Shortcuts and other tools can find the correct installation
/opt/homebrew/opt/python@3.14/bin/python3.14 convert_emails.py
