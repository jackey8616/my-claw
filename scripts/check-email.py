#!/usr/bin/env python3
"""Fetch unseen Gmail messages and print as JSON. Marks fetched messages as seen."""
import imaplib
import email
import json
import os
import sys
from email.header import decode_header


def decode_str(value):
    if not value:
        return ""
    parts = decode_header(value)
    result = []
    for part, charset in parts:
        if isinstance(part, bytes):
            result.append(part.decode(charset or "utf-8", errors="replace"))
        else:
            result.append(part)
    return "".join(result)


def get_body(msg):
    if msg.is_multipart():
        for part in msg.walk():
            ct = part.get_content_type()
            disp = str(part.get("Content-Disposition", ""))
            if ct == "text/plain" and "attachment" not in disp:
                return part.get_payload(decode=True).decode(
                    part.get_content_charset() or "utf-8", errors="replace"
                )
    else:
        return msg.get_payload(decode=True).decode(
            msg.get_content_charset() or "utf-8", errors="replace"
        )
    return ""


def main():
    user = os.environ.get("GMAIL_USER")
    password = os.environ.get("GMAIL_APP_PASSWORD")
    if not user or not password:
        print(json.dumps({"error": "Missing GMAIL_USER or GMAIL_APP_PASSWORD"}))
        sys.exit(1)

    mail = imaplib.IMAP4_SSL("imap.gmail.com", 993)
    mail.login(user, password)
    mail.select("INBOX")

    _, data = mail.search(None, "UNSEEN")
    ids = data[0].split()

    if not ids:
        print(json.dumps({"count": 0, "messages": []}))
        return

    messages = []
    for uid in ids:
        _, msg_data = mail.fetch(uid, "(RFC822)")
        raw = msg_data[0][1]
        msg = email.message_from_bytes(raw)
        messages.append({
            "from": decode_str(msg.get("From", "")),
            "to": decode_str(msg.get("To", "")),
            "subject": decode_str(msg.get("Subject", "")),
            "date": msg.get("Date", ""),
            "body": (get_body(msg) or "").strip()[:2000],
        })
        # mark as seen
        mail.store(uid, "+FLAGS", "\\Seen")

    mail.logout()
    print(json.dumps({"count": len(messages), "messages": messages}, ensure_ascii=False))


if __name__ == "__main__":
    main()
