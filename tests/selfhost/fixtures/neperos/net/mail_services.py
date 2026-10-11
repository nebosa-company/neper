"""A small IMAP4rev1 and SMTP server for the Mail app's fixture (C128), on loopback.

  TCP 8143  IMAP: CAPABILITY, LOGIN (neper / secret), LIST, SELECT, (UID) FETCH, STORE, NOOP, LOGOUT over a
            three-message INBOX
  TCP 8025  SMTP: EHLO, MAIL FROM, RCPT TO, DATA, RSET, QUIT; every accepted message is appended to SENT and,
            so a test can see it, is also available as the INBOX's fourth message after delivery

The guest reaches both at 10.0.2.2 (the name neper.test resolves there). Plain text: the TLS paths of the client
libraries have their own fixtures.
"""
import socketserver
import threading

MESSAGES = [
    (b"Maya Chen <maya@neper.test>", b"Lunch on Friday?", b"Fri, 09 Oct 2026 10:15:00 +0000",
     b"Hi! Are you free for lunch on Friday at 12:30? There is a new place near the library."),
    (b"City Library <desk@library.test>", b"Your hold is ready", b"Fri, 09 Oct 2026 08:00:00 +0000",
     b"The book you reserved is ready for pickup at the front desk."),
    (b"Alex Rivera <alex@neper.test>", b"Build is green", b"Thu, 08 Oct 2026 17:30:00 +0000",
     b"The nightly build passed all tests."),
]
SENT = []
LOCK = threading.Lock()


def render(sender, subject, date, body):
    return (b"From: " + sender + b"\r\nTo: neper@neper.test\r\nSubject: " + subject + b"\r\nDate: " + date +
            b"\r\nMessage-ID: <" + str(abs(hash(subject)) % 100000).encode() + b"@neper.test>\r\n"
            b"MIME-Version: 1.0\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n" + body + b"\r\n")


class Imap(socketserver.StreamRequestHandler):
    def reply(self, data):
        self.wfile.write(data)
        self.wfile.flush()

    def handle(self):
        self.reply(b"* OK IMAP4rev1 neper test server ready\r\n")
        flags = {}
        while True:
            line = self.rfile.readline()
            if not line:
                return
            parts = line.decode("latin-1").rstrip("\r\n").split(" ", 2)
            tag = parts[0]
            command = parts[1].upper() if len(parts) > 1 else ""
            rest = parts[2] if len(parts) > 2 else ""
            with LOCK:
                inbox = list(MESSAGES)
            if command == "CAPABILITY":
                self.reply(b"* CAPABILITY IMAP4rev1 UIDPLUS\r\n" + tag.encode() + b" OK CAPABILITY completed\r\n")
            elif command == "LOGIN":
                ok = rest.replace('"', "").split(" ") == ["neper", "secret"]
                self.reply(tag.encode() + (b" OK LOGIN completed\r\n" if ok else b" NO LOGIN failed\r\n"))
            elif command == "LIST":
                self.reply(b'* LIST (\\HasNoChildren) "/" "INBOX"\r\n' + tag.encode() + b" OK LIST completed\r\n")
            elif command == "SELECT" or command == "EXAMINE":
                n = len(inbox)
                self.reply(("* %d EXISTS\r\n* 0 RECENT\r\n* OK [UIDVALIDITY 1] valid\r\n* OK [UIDNEXT %d] next\r\n"
                            "* FLAGS (\\Seen \\Flagged)\r\n" % (n, n + 1)).encode() + tag.encode() +
                           b" OK [READ-WRITE] SELECT completed\r\n")
            elif command in ("FETCH", "UID"):
                text = rest if command == "FETCH" else rest.split(" ", 1)[1] if " " in rest else rest
                by_uid = command == "UID"
                if by_uid:
                    sub = rest.split(" ", 2)
                    text = " ".join(sub[1:])
                spec = text.split(" ", 1)[0]
                first, _, last = spec.partition(":")
                low = int(first)
                high = len(inbox) if last in ("*", "") and ":" in spec else int(last or first)
                out = b""
                for n in range(low, min(high, len(inbox)) + 1):
                    sender, subject, date, body = inbox[n - 1]
                    raw = render(sender, subject, date, body)
                    seen = b"\\Seen" if flags.get(n) else b""
                    out += (b"* %d FETCH (" % n) + (b"UID %d " % n if by_uid or b"UID" in text.encode() else b"") + \
                        b"FLAGS (" + seen + b") BODY[] {%d}\r\n" % len(raw) + raw + b")\r\n"
                self.reply(out + tag.encode() + b" OK FETCH completed\r\n")
            elif command == "STORE":
                self.reply(tag.encode() + b" OK STORE completed\r\n")
            elif command == "NOOP":
                self.reply(tag.encode() + b" OK NOOP completed\r\n")
            elif command == "LOGOUT":
                self.reply(b"* BYE logging out\r\n" + tag.encode() + b" OK LOGOUT completed\r\n")
                return
            else:
                self.reply(tag.encode() + b" BAD unknown command\r\n")


class Smtp(socketserver.StreamRequestHandler):
    def reply(self, data):
        self.wfile.write(data)
        self.wfile.flush()

    def handle(self):
        self.reply(b"220 neper.test ESMTP ready\r\n")
        sender = b""
        recipients = []
        while True:
            line = self.rfile.readline()
            if not line:
                return
            text = line.decode("latin-1").rstrip("\r\n")
            upper = text.upper()
            if upper.startswith("EHLO") or upper.startswith("HELO"):
                self.reply(b"250-neper.test\r\n250-SIZE 1048576\r\n250 8BITMIME\r\n")
            elif upper.startswith("MAIL FROM"):
                sender = text.split(":", 1)[1].strip().encode()
                recipients = []
                self.reply(b"250 2.1.0 ok\r\n")
            elif upper.startswith("RCPT TO"):
                recipients.append(text.split(":", 1)[1].strip().encode())
                self.reply(b"250 2.1.5 ok\r\n")
            elif upper == "DATA":
                self.reply(b"354 end data with <CR><LF>.<CR><LF>\r\n")
                data = b""
                while True:
                    chunk = self.rfile.readline()
                    if chunk in (b".\r\n", b""):
                        break
                    data += chunk[1:] if chunk.startswith(b"..") else chunk
                with LOCK:
                    SENT.append((sender, recipients, data))
                self.reply(b"250 2.0.0 queued as %d\r\n" % len(SENT))
            elif upper == "RSET":
                self.reply(b"250 ok\r\n")
            elif upper == "NOOP":
                self.reply(b"250 ok\r\n")
            elif upper == "QUIT":
                self.reply(b"221 bye\r\n")
                return
            else:
                self.reply(b"500 unknown command\r\n")


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def start():
    for port, handler in ((8143, Imap), (8025, Smtp)):
        server = Server(("127.0.0.1", port), handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
