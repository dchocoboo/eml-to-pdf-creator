#!/bin/bash
# Double-click this file in Finder to convert all .eml files in the input folder

cd "$(dirname "$0")"
python3 convert_emails.py
