"""A small IMAP4rev1 and SMTP server for the Mail app's fixture (C128), on loopback.

  TCP 8143  IMAP: CAPABILITY, LOGIN (neper / secret, and ada / lovelace), LIST, SELECT, (UID) FETCH, (UID) STORE,
            EXPUNGE, NOOP, LOGOUT over a three-message INBOX; flags and deletions are kept for the life of the
            process, so a later session sees what an earlier one did
  TCP 8993  the IMAP service over TLS 1.3 and 8465 the SMTP one (the client tries these first)
  TCP 8025  SMTP: EHLO, MAIL FROM, RCPT TO, DATA, RSET, QUIT; every accepted message is kept in SENT

(C158) neper has more folders than the INBOX, selected by name: Archive (a three-message thread and a receipt),
Updates (an HTML newsletter with an inline PNG named by Content-ID) and Sent (what SMTP accepted, as sent). ada has
her own INBOX of one message. Flags and deletions are kept per (user, folder, uid).

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
ARCHIVE = [
    (b"Maya Chen <maya@neper.test>", b"Trip plan", b"Mon, 05 Oct 2026 09:00:00 +0000",
     b"Shall we take the coast road on Saturday?"),
    (b"Alex Rivera <alex@neper.test>", b"Re: Trip plan", b"Mon, 05 Oct 2026 11:30:00 +0000",
     b"Coast road is fine, I will bring the maps."),
    (b"Maya Chen <maya@neper.test>", b"Re: Trip plan", b"Tue, 06 Oct 2026 08:10:00 +0000",
     b"Great, leaving at 8."),
    (b"Neper Bank <bank@neper.test>", b"Old receipt", b"Sun, 20 Sep 2026 12:00:00 +0000",
     b"Your receipt for September."),
]
UPDATES = [(b"Neper News <news@neper.test>", b"October update", b"Tue, 13 Oct 2026 07:00:00 +0000", b"")]
ADA_INBOX = [(b"Charles Babbage <cb@neper.test>", b"Engine notes", b"Wed, 07 Oct 2026 10:00:00 +0000",
              b"Dear Ada, the drawings for the engine are done.")]
ACCOUNTS = {"neper": "secret", "ada": "lovelace"}
MENU = b"Friday menu: soup 4, pasta 9, tea 2\n"
SENT = []
SEEN = set()
DELETED = set()
EXPUNGED = set()
LOCK = threading.RLock()
CRLF = b"\r\n"


def newsletter(sender, subject, date):
    """(C158) multipart/related: an HTML body (heading, paragraph, list, link) and an inline PNG named by Content-ID."""
    import base64
    import pathlib
    png = base64.encodebytes((pathlib.Path(__file__).resolve().parent / "logo-24.png").read_bytes())
    html = (b"<html><body><h1>October update</h1><p>This month: the <b>Mail</b> app learned HTML.</p>"
            b"<ul><li>Folders and accounts</li><li>Threads</li></ul>"
            b"<img src=\"cid:logo1\" alt=\"logo\"><p>Read more at <a href=\"https://neper.test/pages/index.html\">neper.test</a>.</p>"
            b"</body></html>")
    boundary = b"=_neper_rel"
    return (b"From: " + sender + b"\r\nTo: neper@neper.test\r\nSubject: " + subject + b"\r\nDate: " + date +
            b"\r\nMessage-ID: <news@neper.test>\r\nMIME-Version: 1.0\r\n"
            b"Content-Type: multipart/related; boundary=\"" + boundary + b"\"\r\n\r\n"
            b"--" + boundary + b"\r\nContent-Type: text/html; charset=utf-8\r\n\r\n" + html + b"\r\n"
            b"--" + boundary + b"\r\nContent-Type: image/png\r\nContent-ID: <logo1>\r\n"
            b"Content-Disposition: inline; filename=\"logo.png\"\r\nContent-Transfer-Encoding: base64\r\n\r\n" +
            png.replace(b"\n", b"\r\n") + b"--" + boundary + b"--\r\n")


def render(sender, subject, date, body):
    if subject is None:
        # A message kept as sent: the bytes the client submitted.
        return sender
    if subject == b"October update":
        return newsletter(sender, subject, date)
    if subject in (b"Trip plan", b"Re: Trip plan"):
        # (C158) A thread: the replies name the first message in In-Reply-To and References.
        extra = b"" if subject == b"Trip plan" else b"In-Reply-To: <trip@neper.test>\r\nReferences: <trip@neper.test>\r\n"
        return (b"From: " + sender + b"\r\nTo: neper@neper.test\r\nSubject: " + subject + b"\r\nDate: " + date +
                b"\r\nMessage-ID: <" + str(abs(hash(date)) % 100000).encode() + b"@neper.test>\r\n" + extra +
                b"MIME-Version: 1.0\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n" + body + b"\r\n")
    if subject == b"Your hold is ready":
        # (C158) HTML only, quoted-printable: the client must undo both to show the text.
        html = b"<html><body><p>The book you reserved is ready for pickup at the <b>front desk</b>.</p></body></html>"
        return (b"From: " + sender + b"\r\nTo: neper@neper.test\r\nSubject: " + subject + b"\r\nDate: " + date +
                b"\r\nMessage-ID: <html@neper.test>\r\nMIME-Version: 1.0\r\n"
                b"Content-Type: text/html; charset=utf-8\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\n" +
                html.replace(b"=", b"=3D") + b"\r\n")
    if subject == b"Lunch on Friday?":
        # (C158) A multipart/mixed: the text and an attachment (menu.txt, base64 over two lines).
        import base64
        boundary = b"=_neper_mixed"
        menu = base64.b64encode(MENU)
        return (b"From: " + sender + b"\r\nTo: neper@neper.test\r\nSubject: " + subject + b"\r\nDate: " + date +
                b"\r\nMessage-ID: <mixed@neper.test>\r\nMIME-Version: 1.0\r\n"
                b"Content-Type: multipart/mixed; boundary=\"" + boundary + b"\"\r\n\r\n"
                b"--" + boundary + b"\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n" + body + b"\r\n"
                b"--" + boundary + b"\r\nContent-Type: text/plain; name=\"menu.txt\"\r\n"
                b"Content-Disposition: attachment; filename=\"menu.txt\"\r\nContent-Transfer-Encoding: base64\r\n\r\n" +
                menu[:32] + b"\r\n" + menu[32:] + b"\r\n"
                b"--" + boundary + b"--\r\n")
    if subject == b"Build is green":
        # A multipart/alternative: the plain part first, an HTML part after.
        boundary = b"=_neper_alt"
        return (b"From: " + sender + b"\r\nTo: neper@neper.test\r\nSubject: " + subject + b"\r\nDate: " + date +
                b"\r\nMessage-ID: <alt@neper.test>\r\nMIME-Version: 1.0\r\n"
                b"Content-Type: multipart/alternative; boundary=\"" + boundary + b"\"\r\n\r\n"
                b"--" + boundary + b"\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n" + body + b"\r\n"
                b"--" + boundary + b"\r\nContent-Type: text/html; charset=utf-8\r\n\r\n<p>" + body + b"</p>\r\n"
                b"--" + boundary + b"--\r\n")
    return (b"From: " + sender + b"\r\nTo: neper@neper.test\r\nSubject: " + subject + b"\r\nDate: " + date +
            b"\r\nMessage-ID: <" + str(abs(hash(subject)) % 100000).encode() + b"@neper.test>\r\n"
            b"MIME-Version: 1.0\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n" + body + b"\r\n")


class Imap(socketserver.StreamRequestHandler):
    user = None
    folder = "INBOX"

    def reply(self, data):
        self.wfile.write(data)
        self.wfile.flush()

    def items(self):
        """What the selected folder holds, in order: render tuples (a sent message as its raw bytes)."""
        if self.user == "ada":
            return ADA_INBOX if self.folder == "INBOX" else []
        if self.folder == "INBOX":
            return MESSAGES
        if self.folder == "Archive":
            return ARCHIVE
        if self.folder == "Updates":
            return UPDATES
        if self.folder == "Sent":
            with LOCK:
                return [(data, None, None, None) for (_, _, data) in SENT]
        return []

    def view(self):
        """The selected folder as a client sees it: (uid, message) for what is not expunged, in order."""
        with LOCK:
            return [(i + 1, m) for i, m in enumerate(self.items()) if (self.user, self.folder, i + 1) not in EXPUNGED]

    def handle(self):
        self.reply(b"* OK IMAP4rev1 neper test server ready" + CRLF)
        while True:
            line = self.rfile.readline()
            if not line:
                return
            parts = line.decode("latin-1").rstrip("\r\n").split(" ", 2)
            tag = parts[0].encode()
            command = parts[1].upper() if len(parts) > 1 else ""
            rest = parts[2] if len(parts) > 2 else ""
            by_uid = False
            if command == "UID":
                by_uid = True
                sub = rest.split(" ", 1)
                command = sub[0].upper()
                rest = sub[1] if len(sub) > 1 else ""
            inbox = self.view()
            if command == "CAPABILITY":
                self.reply(b"* CAPABILITY IMAP4rev1 UIDPLUS" + CRLF + tag + b" OK CAPABILITY completed" + CRLF)
            elif command == "LOGIN":
                pair = rest.replace('"', "").split(" ")
                ok = len(pair) == 2 and ACCOUNTS.get(pair[0]) == pair[1]
                if ok:
                    self.user = pair[0]
                self.reply(tag + (b" OK LOGIN completed" if ok else b" NO LOGIN failed") + CRLF)
            elif command == "LIST":
                names = ["INBOX"] if self.user == "ada" else ["INBOX", "Archive", "Updates", "Sent"]
                listing = b"".join(b'* LIST (\\HasNoChildren) "/" "' + n.encode() + b'"' + CRLF for n in names)
                self.reply(listing + tag + b" OK LIST completed" + CRLF)
            elif command in ("SELECT", "EXAMINE"):
                self.folder = rest.replace('"', "").strip() or "INBOX"
                inbox = self.view()
                self.reply(("* %d EXISTS\r\n* 0 RECENT\r\n* OK [UIDVALIDITY 1] valid\r\n* OK [UIDNEXT %d] next\r\n"
                            "* FLAGS (\\Seen \\Flagged \\Deleted)\r\n" % (len(inbox), len(self.items()) + 1)).encode() +
                           tag + b" OK [READ-WRITE] SELECT completed" + CRLF)
            elif command == "FETCH":
                spec = rest.split(" ", 1)[0]
                first, _, last = spec.partition(":")
                low = int(first)
                high = (10 ** 6 if last == "*" else int(last)) if ":" in spec else low
                out = b""
                for position, (uid, message) in enumerate(inbox, 1):
                    key = uid if by_uid else position
                    if not low <= key <= high:
                        continue
                    raw = render(*message)
                    with LOCK:
                        flags = b"\\Seen" if (self.user, self.folder, uid) in SEEN else b""
                    out += (b"* %d FETCH (UID %d FLAGS (" % (position, uid)) + flags + b") BODY[] {%d}\r\n" % len(raw) + raw + b")\r\n"
                self.reply(out + tag + b" OK FETCH completed" + CRLF)
            elif command == "STORE":
                spec, _, action = rest.partition(" ")
                wanted = {int(x) for x in spec.split(",") if x.isdigit()}
                for position, (uid, message) in enumerate(inbox, 1):
                    if (uid if by_uid else position) in wanted:
                        with LOCK:
                            if "\\Seen" in action:
                                SEEN.add((self.user, self.folder, uid))
                            if "\\Deleted" in action:
                                DELETED.add((self.user, self.folder, uid))
                self.reply(tag + b" OK STORE completed" + CRLF)
            elif command == "EXPUNGE":
                out = b""
                with LOCK:
                    for position, (uid, message) in enumerate(inbox, 1):
                        if (self.user, self.folder, uid) in DELETED:
                            EXPUNGED.add((self.user, self.folder, uid))
                            out += b"* %d EXPUNGE\r\n" % position
                self.reply(out + tag + b" OK EXPUNGE completed" + CRLF)
            elif command == "NOOP":
                self.reply(tag + b" OK NOOP completed" + CRLF)
            elif command == "LOGOUT":
                self.reply(b"* BYE logging out" + CRLF + tag + b" OK LOGOUT completed" + CRLF)
                return
            else:
                self.reply(tag + b" BAD unknown command" + CRLF)


class Smtp(socketserver.StreamRequestHandler):
    def reply(self, data):
        self.wfile.write(data)
        self.wfile.flush()

    def handle(self):
        self.reply(b"220 neper.test ESMTP ready" + CRLF)
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
                self.reply(b"250 2.1.0 ok" + CRLF)
            elif upper.startswith("RCPT TO"):
                recipients.append(text.split(":", 1)[1].strip().encode())
                self.reply(b"250 2.1.5 ok" + CRLF)
            elif upper == "DATA":
                self.reply(b"354 end data with <CR><LF>.<CR><LF>" + CRLF)
                data = b""
                while True:
                    chunk = self.rfile.readline()
                    if chunk in (b".\r\n", b""):
                        break
                    data += chunk[1:] if chunk.startswith(b"..") else chunk
                with LOCK:
                    SENT.append((sender, recipients, data))
                self.reply(b"250 2.0.0 queued as %d\r\n" % len(SENT))
            elif upper in ("RSET", "NOOP"):
                self.reply(b"250 ok" + CRLF)
            elif upper == "QUIT":
                self.reply(b"221 bye" + CRLF)
                return
            else:
                self.reply(b"500 unknown command" + CRLF)


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def start():
    import pathlib
    import ssl
    here = pathlib.Path(__file__).resolve().parent
    for port, handler in ((8143, Imap), (8025, Smtp)):
        server = Server(("127.0.0.1", port), handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
    # The same two over TLS 1.3 (the leaf certificate of the fixture CA, as the HTTPS service uses).
    for port, handler in ((8993, Imap), (8465, Smtp)):
        server = Server(("127.0.0.1", port), handler)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = ssl.TLSVersion.TLSv1_3
        context.load_cert_chain(str(here / "server.pem"), str(here / "server.key"))
        server.socket = context.wrap_socket(server.socket, server_side=True)
        threading.Thread(target=server.serve_forever, daemon=True).start()
