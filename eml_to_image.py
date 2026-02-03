#!/usr/bin/env python3
"""
EML to PNG/PDF Converter

Converts email (.eml) files to PNG images and PDF documents.
Handles HTML emails, plain text emails, and embedded images.
"""

import argparse
import base64
import email
import html
import os
import re
import tempfile
from email import policy
from email.message import EmailMessage
from pathlib import Path
from typing import Optional

from playwright.sync_api import sync_playwright


def parse_eml(eml_path: str) -> EmailMessage:
    """Parse an EML file and return an EmailMessage object."""
    with open(eml_path, 'rb') as f:
        return email.message_from_binary_file(f, policy=policy.default)


def extract_email_content(msg: EmailMessage) -> tuple[str, dict[str, bytes]]:
    """
    Extract HTML/text content and embedded images from an email.
    
    Returns:
        tuple: (html_content, dict of cid -> image_bytes)
    """
    html_content = None
    text_content = None
    embedded_images = {}
    
    if msg.is_multipart():
        for part in msg.walk():
            content_type = part.get_content_type()
            content_disposition = str(part.get("Content-Disposition", ""))
            
            # Extract embedded images (inline attachments)
            if content_type.startswith("image/"):
                content_id = part.get("Content-ID", "")
                if content_id:
                    # Remove angle brackets from Content-ID
                    cid = content_id.strip("<>")
                    payload = part.get_payload(decode=True)
                    if payload:
                        embedded_images[cid] = (content_type, payload)
            
            # Extract HTML content
            elif content_type == "text/html" and "attachment" not in content_disposition:
                charset = part.get_content_charset() or 'utf-8'
                payload = part.get_payload(decode=True)
                if payload:
                    html_content = payload.decode(charset, errors='replace')
            
            # Extract plain text as fallback
            elif content_type == "text/plain" and "attachment" not in content_disposition:
                charset = part.get_content_charset() or 'utf-8'
                payload = part.get_payload(decode=True)
                if payload:
                    text_content = payload.decode(charset, errors='replace')
    else:
        content_type = msg.get_content_type()
        charset = msg.get_content_charset() or 'utf-8'
        payload = msg.get_payload(decode=True)
        
        if payload:
            if content_type == "text/html":
                html_content = payload.decode(charset, errors='replace')
            else:
                text_content = payload.decode(charset, errors='replace')
    
    # Use HTML content if available, otherwise convert plain text to HTML
    if html_content:
        final_content = html_content
    elif text_content:
        final_content = plain_text_to_html(text_content)
    else:
        final_content = "<html><body><p>No content found</p></body></html>"
    
    return final_content, embedded_images


def plain_text_to_html(text: str) -> str:
    """Convert plain text email to HTML."""
    escaped = html.escape(text)
    # Convert URLs to clickable links
    url_pattern = r'(https?://[^\s<>"]+)'
    escaped = re.sub(url_pattern, r'<a href="\1">\1</a>', escaped)
    # Preserve line breaks
    escaped = escaped.replace('\n', '<br>\n')
    
    return f"""<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <style>
        body {{
            font-family: 'Courier New', monospace;
            font-size: 14px;
            line-height: 1.5;
            padding: 20px;
            white-space: pre-wrap;
        }}
    </style>
</head>
<body>
{escaped}
</body>
</html>"""


def format_email_header(msg: EmailMessage) -> str:
    """Format email headers as HTML."""
    headers = []
    
    # Get common headers
    from_addr = msg.get("From", "Unknown")
    to_addr = msg.get("To", "Unknown")
    cc_addr = msg.get("Cc", "")
    subject = msg.get("Subject", "No Subject")
    date = msg.get("Date", "Unknown Date")
    
    headers.append(f"<strong>From:</strong> {html.escape(str(from_addr))}")
    headers.append(f"<strong>To:</strong> {html.escape(str(to_addr))}")
    if cc_addr:
        headers.append(f"<strong>Cc:</strong> {html.escape(str(cc_addr))}")
    headers.append(f"<strong>Date:</strong> {html.escape(str(date))}")
    headers.append(f"<strong>Subject:</strong> {html.escape(str(subject))}")
    
    return "<br>\n".join(headers)


def embed_images_as_base64(html_content: str, embedded_images: dict[str, tuple[str, bytes]]) -> str:
    """Replace cid: references with base64 encoded images."""
    for cid, (content_type, image_data) in embedded_images.items():
        b64_data = base64.b64encode(image_data).decode('ascii')
        data_uri = f"data:{content_type};base64,{b64_data}"
        
        # Replace various cid reference formats
        html_content = html_content.replace(f'cid:{cid}', data_uri)
        html_content = html_content.replace(f'CID:{cid}', data_uri)
    
    return html_content


def create_full_html(msg: EmailMessage, body_html: str, embedded_images: dict) -> str:
    """Create a complete HTML document with headers and body."""
    header_html = format_email_header(msg)
    body_html = embed_images_as_base64(body_html, embedded_images)
    
    # Check if body already has complete HTML structure
    has_html_tag = '<html' in body_html.lower()
    has_body_tag = '<body' in body_html.lower()
    
    if has_html_tag and has_body_tag:
        # Inject headers into existing HTML
        # Try to find body tag and inject after it
        body_pattern = re.compile(r'(<body[^>]*>)', re.IGNORECASE)
        header_block = f'''
        <div style="background-color: #f5f5f5; padding: 15px; margin-bottom: 20px; 
                    border-bottom: 2px solid #ddd; font-family: Arial, sans-serif; font-size: 13px;">
            {header_html}
        </div>
        '''
        
        if body_pattern.search(body_html):
            body_html = body_pattern.sub(r'\1' + header_block, body_html, count=1)
        
        return body_html
    else:
        # Wrap in complete HTML structure
        return f"""<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <style>
        body {{
            font-family: Arial, sans-serif;
            max-width: 900px;
            margin: 0 auto;
            padding: 20px;
            background-color: white;
        }}
        .email-header {{
            background-color: #f5f5f5;
            padding: 15px;
            margin-bottom: 20px;
            border-bottom: 2px solid #ddd;
            font-size: 13px;
        }}
        .email-body {{
            line-height: 1.6;
        }}
    </style>
</head>
<body>
    <div class="email-header">
        {header_html}
    </div>
    <div class="email-body">
        {body_html}
    </div>
</body>
</html>"""


def render_to_png_pdf(html_content: str, output_base: str, width: int = 800, scale: float = 2.0):
    """
    Render HTML content to PNG and PDF using Playwright.
    
    Args:
        html_content: The HTML content to render
        output_base: Base path for output files (without extension)
        width: Viewport width for rendering
        scale: Device scale factor for PNG (2.0 = retina quality)
    """
    png_path = f"{output_base}.png"
    pdf_path = f"{output_base}.pdf"
    
    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page(viewport={"width": width, "height": 800}, device_scale_factor=scale)
        
        # Create a temporary HTML file
        with tempfile.NamedTemporaryFile(mode='w', suffix='.html', delete=False, encoding='utf-8') as f:
            f.write(html_content)
            temp_html_path = f.name
        
        try:
            # Load the HTML file
            page.goto(f'file://{temp_html_path}')
            
            # Wait for any images to load
            page.wait_for_load_state('networkidle')
            
            # Get the full page height
            full_height = page.evaluate('document.documentElement.scrollHeight')
            
            # Resize viewport to full content height for screenshot
            page.set_viewport_size({"width": width, "height": full_height})
            
            # Take full page screenshot as PNG
            page.screenshot(path=png_path, full_page=True)
            print(f"Created PNG: {png_path}")
            
            # Generate PDF without page breaks
            # Using a very long page to avoid breaks
            page.pdf(
                path=pdf_path,
                width=f"{width}px",
                height=f"{full_height + 100}px",  # Add some padding
                print_background=True,
                margin={"top": "20px", "right": "20px", "bottom": "20px", "left": "20px"}
            )
            print(f"Created PDF: {pdf_path}")
            
        finally:
            os.unlink(temp_html_path)
            browser.close()


def convert_eml(eml_path: str, output_dir: Optional[str] = None, width: int = 800, scale: float = 2.0):
    """
    Convert an EML file to PNG and PDF.
    
    Args:
        eml_path: Path to the EML file
        output_dir: Output directory (defaults to same as input file)
        width: Viewport width for rendering
        scale: Device scale factor for PNG (2.0 = retina quality)
    """
    eml_path = Path(eml_path)
    
    if not eml_path.exists():
        raise FileNotFoundError(f"EML file not found: {eml_path}")
    
    if output_dir:
        output_dir = Path(output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)
    else:
        output_dir = eml_path.parent
    
    output_base = output_dir / eml_path.stem
    
    print(f"Processing: {eml_path}")
    
    # Parse the email
    msg = parse_eml(str(eml_path))
    
    # Extract content
    body_html, embedded_images = extract_email_content(msg)
    
    # Create full HTML with headers
    full_html = create_full_html(msg, body_html, embedded_images)
    
    # Render to PNG and PDF
    render_to_png_pdf(full_html, str(output_base), width, scale)
    
    # Extract attachments
    extract_attachments(msg, output_dir / f"{eml_path.stem}_attachments")
    
    print(f"Conversion complete for: {eml_path.name}")


def extract_attachments(msg: EmailMessage, output_dir: Path):
    """
    Extract attachments from an email and save them to a directory.
    
    Args:
        msg: The parsed EmailMessage object
        output_dir: Directory to save attachments to
    """
    attachments_found = False
    
    if msg.is_multipart():
        for part in msg.walk():
            content_disposition = str(part.get("Content-Disposition", ""))
            
            if "attachment" in content_disposition:
                filename = part.get_filename()
                if filename:
                    if not attachments_found:
                        output_dir.mkdir(parents=True, exist_ok=True)
                        attachments_found = True
                        print(f"Extracting attachments to: {output_dir}")
                    
                    filepath = output_dir / filename
                    
                    # Handle duplicate filenames
                    counter = 1
                    while filepath.exists():
                        name_stem = Path(filename).stem
                        suffix = Path(filename).suffix
                        filepath = output_dir / f"{name_stem}_{counter}{suffix}"
                        counter += 1
                        
                    payload = part.get_payload(decode=True)
                    if payload:
                        with open(filepath, "wb") as f:
                            f.write(payload)
                        print(f"  - Saved: {filepath.name}")



def main():
    parser = argparse.ArgumentParser(
        description="Convert EML email files to PNG and PDF",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s email.eml
  %(prog)s email.eml -o ./output
  %(prog)s *.eml -w 1024
  %(prog)s emails/*.eml -o ./rendered
        """
    )
    
    parser.add_argument(
        "eml_files",
        nargs="+",
        help="EML file(s) to convert"
    )
    
    parser.add_argument(
        "-o", "--output",
        help="Output directory (defaults to same directory as input file)"
    )
    
    parser.add_argument(
        "-w", "--width",
        type=int,
        default=800,
        help="Viewport width for rendering (default: 800)"
    )
    
    parser.add_argument(
        "-s", "--scale",
        type=float,
        default=2.0,
        help="Device scale factor for PNG quality (default: 2.0 for retina)"
    )
    
    args = parser.parse_args()
    
    for eml_file in args.eml_files:
        try:
            convert_eml(eml_file, args.output, args.width, args.scale)
        except Exception as e:
            print(f"Error processing {eml_file}: {e}")


if __name__ == "__main__":
    main()
