#!/usr/bin/env python3
"""
EML to PNG/PDF Converter Launcher

Double-click to convert all .eml files in the input folder.
"""

import os
import sys
import subprocess
from pathlib import Path


def main():
    # Get the directory where this script is located
    script_dir = Path(__file__).parent.resolve()
    input_dir = script_dir / "input"
    output_dir = script_dir / "output"

    print("=" * 50)
    print("EML to PNG/PDF Converter")
    print("=" * 50)
    print()
    print(f"Input folder:  {input_dir}")
    print(f"Output folder: {output_dir}")
    print()

    # Create folders if they don't exist
    input_dir.mkdir(exist_ok=True)
    output_dir.mkdir(exist_ok=True)

    # Check if playwright is installed
    try:
        import playwright  # noqa: F401
    except ImportError:
        print("Error: 'playwright' library is not installed.")
        print("Please run: pip3 install -r requirements.txt && playwright install chromium")
        print()
        input("Press Enter to close...")
        sys.exit(1)

    # Find all .eml files in input folder
    eml_files = list(input_dir.glob("*.eml"))

    if not eml_files:
        print("No .eml files found in input folder.")
        print(f"Please put your .eml files in: {input_dir}")
        print()
        # input("Press Enter to close...")
        sys.exit(0)

    print("Found the following .eml files:")
    for file in eml_files:
        print(f"  - {file.name}")
    print()

    # Convert each .eml file
    print("Starting conversion...")
    print()

    result = subprocess.run(
        [
            sys.executable,
            str(script_dir / "eml_to_image.py"),
            *[str(f) for f in eml_files],
            "-o",
            str(output_dir),
        ]
    )

    print()
    print("=" * 50)
    if result.returncode == 0:
        print("Conversion complete!")
    else:
        print("Conversion finished with errors.")
    print(f"Output files are in: {output_dir}")
    print("=" * 50)
    print()
    input("Press Enter to close...")


if __name__ == "__main__":
    main()
