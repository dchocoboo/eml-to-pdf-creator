import email
from email.message import EmailMessage
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

def create_japanese_eml(filename):
    msg = MIMEMultipart()
    msg['Subject'] = '日本語のテスト (Japanese Test)'
    msg['From'] = 'sender@example.com'
    msg['To'] = 'recipient@example.com'

    # Body in ISO-2022-JP
    body_text = "これはテストです。"

    # HTML Body with explicit charset meta tag
    html_content = f"""<html>
<head>
    <meta http-equiv="Content-Type" content="text/html; charset=iso-2022-jp">
</head>
<body>
    <p>{body_text}</p>
    <p>Japanese: 日本語</p>
</body>
</html>"""

    # Attach text part
    part = MIMEText(html_content, 'html', 'iso-2022-jp')
    msg.attach(part)

    with open(filename, 'wb') as f:
        f.write(msg.as_bytes())
    print(f"Created {filename}")

if __name__ == "__main__":
    create_japanese_eml("input/test_jp.eml")
