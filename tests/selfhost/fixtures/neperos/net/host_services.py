"""The host side of the NeperOS network fixture (C117): everything the guest reaches at 10.0.2.2.

  python host_services.py [ready-file]

  UDP 5300  a DNS responder answering every A query with 10.0.2.2 (the guest names the resolver
            explicitly, so the fixture needs no internet and no privileged port)
  TCP 8081  HTTP
  TCP 8090  ws and 8453 wss: the Chat app's test server (chat_services.py)
  TCP 8143  IMAP and 8025  SMTP (mail_services.py): the Mail app's test accounts
  TCP 8022  SSH (asyncssh): user neper, password secret, a shell that upper-cases a line, `exit` ends with 7
  TCP 8443  HTTPS, TLS 1.3 only, the leaf certificate signed by the fixture CA (names neper.test,
            api.exchange.coinbase.com, api.twelvedata.com, www.alphavantage.co, api.polygon.io); besides the plain
            page it answers the Stocks fixture's APIs from the recordings made by record.py

Writes the ready-file once all three listen, then serves until killed.
"""
import http.server
import json
import pathlib
import socket
import ssl
import struct
import urllib.parse
import sys
import threading

here = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(here))
import ai_services
BODY = b'hello from the neper test server\n'
# (C151) The Dynamic build server (dynamic_services.py needs `cryptography`, as scripts/make_package.py does).
sys.path.insert(0, str(here))
try:
    import dynamic_services as DYNAMIC
except ImportError:
    DYNAMIC = None
# (C159, C160, C156) More web pages, map and weather feeds for the Browser, Maps and Weather fixtures.
import web_services as WEB

# The test boot's translation "model": a word-for-word dictionary through English, six languages.
WORDS = [
    ('hello', 'hola', 'bonjour', 'hallo', 'ciao', 'ola'),
    ('good', 'bueno', 'bon', 'gut', 'buono', 'bom'),
    ('morning', 'manana', 'matin', 'morgen', 'mattina', 'manha'),
    ('night', 'noche', 'nuit', 'nacht', 'notte', 'noite'),
    ('thank', 'gracias', 'merci', 'danke', 'grazie', 'obrigado'),
    ('you', 'tu', 'vous', 'du', 'tu', 'voce'),
    ('where', 'donde', 'ou', 'wo', 'dove', 'onde'),
    ('is', 'es', 'est', 'ist', 'e', 'e'),
    ('the', 'el', 'le', 'der', 'il', 'o'),
    ('library', 'biblioteca', 'bibliotheque', 'bibliothek', 'biblioteca', 'biblioteca'),
    ('coffee', 'cafe', 'cafe', 'kaffee', 'caffe', 'cafe'),
    ('water', 'agua', 'eau', 'wasser', 'acqua', 'agua'),
    ('friend', 'amigo', 'ami', 'freund', 'amico', 'amigo'),
    ('house', 'casa', 'maison', 'haus', 'casa', 'casa'),
    ('book', 'libro', 'livre', 'buch', 'libro', 'livro'),
    ('please', 'por favor', 'sil vous plait', 'bitte', 'per favore', 'por favor'),
]
CODES = ['en', 'es', 'fr', 'de', 'it', 'pt']


def translate(source, target, text):
    if source not in CODES or target not in CODES:
        return text
    a, b = CODES.index(source), CODES.index(target)
    out = []
    for word in text.lower().split():
        for row in WORDS:
            if row[a] == word:
                out.append(row[b])
                break
        else:
            out.append(word)
    return ' '.join(out)


PAGE_INDEX = (b'<!doctype html><html><head><title>Neper test page</title><style>p{color:red}</style></head><body>'
              b'<h1>Neper test page</h1>'
              b'<p>This page is served by the test boot and laid out by the browser from real HTML, '
              b'with a paragraph long enough to wrap onto more than one line.</p>'
              b'<h2>A list</h2><ul><li>first item</li><li>second item</li><li>third item</li></ul>'
              b'<p>Read more on the <a href="/pages/about.html">about page</a> or go <a href="https://neper.test/">home</a>.</p>'
              b'<p><a href="/pages/old.html">Moved page</a></p>'
              b'</body></html>')
PAGE_ABOUT = (b'<!doctype html><html><head><title>About</title></head><body>'
              b'<h1>About</h1><p>Neper is a language and an operating system.</p>'
              b'<p><a href="/pages/index.html">Back to the index</a></p>'
              b'<p><a href="/pages/login.html">Sign in</a></p>'
              b'<p><a href="/pages/form.html">Search form</a></p></body></html>')
# (C159) A page with an image and a form (GET), the page the form's query reaches, and a file to download.
PAGE_FORM = (b'<!doctype html><html><head><title>Search form</title></head><body>'
             b'<h1>Search form</h1><img src="/pages/logo.svg" alt="logo">'
             b'<form action="/pages/echo.html" method="get">'
             b'<input type="text" name="q" value="neper os"><input type="hidden" name="lang" value="en">'
             b'<input type="submit" value="Go"></form></body></html>')
LOGO_SVG = (b"<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 96 96'>"
            b"<rect x='4' y='4' width='88' height='88' rx='12' fill='currentColor'/>"
            b"<circle cx='48' cy='48' r='24' fill='none' stroke='white' stroke-width='6'/></svg>")
REPORT_BIN = bytes(range(32)) + b'neper report 2026-10-12'
# (C159) A page that sets a session cookie and one that says what cookie it was sent.
PAGE_LOGIN = (b'<!doctype html><html><head><title>Signed in</title></head><body>'
              b'<h1>Signed in</h1><p><a href="/pages/me.html">Account</a></p></body></html>')


def recorded(name):
    return (here / name).read_bytes()


class Handler(http.server.BaseHTTPRequestHandler):
    def reply(self, status, body, kind='text/plain', headers=()):
        self.send_response(status)
        for name, value in headers:
            self.send_header(name, value)
        self.send_header('Content-Type', kind)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        # The Stocks fixture's two APIs, answered from recordings (record.py): Coinbase Exchange's daily
        # candles (no key) and Twelve Data's time_series (the key `demo`, the symbol AAPL).
        url = urllib.parse.urlparse(self.path)
        host = (self.headers.get('Host') or '').split(':')[0]
        query = urllib.parse.parse_qs(url.query)
        # (C151) The Dynamic build server's package and revocation list.
        if DYNAMIC is not None and DYNAMIC.get(self, host, url.path):
            return
        # (C171) The AI providers' model lists (the key check).
        if ai_services.get(self, host, self.path):
        if WEB.get(self, host, url.path, query):
            return
        if host == 'api.exchange.coinbase.com' and url.path == '/products':
            # Public, no key: the curated pair list the Add sheet's crypto Find searches.
            self.reply(200, (here / 'products.json').read_bytes(), 'application/json')
            return
        if host == 'api.exchange.coinbase.com' and url.path.startswith('/products/') and url.path.endswith('/candles'):
            product = url.path.split('/')[2]
            known = here / ('candles-%s.json' % product)
            if known.exists():
                self.reply(200, known.read_bytes(), 'application/json')
            else:
                self.reply(404, b'{"message":"NotFound"}', 'application/json')
            return
        if host == 'api.open-meteo.com' and url.path == '/v1/forecast':
            # Keyless; the recordings are keyed by the latitude the app sends (hundredths of a degree).
            known = {'47.61': 'seattle', '59.91': 'oslo', '60.39': 'bergen'}.get(query.get('latitude', [''])[0])
            if known:
                self.reply(200, (here / ('forecast-%s.json' % known)).read_bytes(), 'application/json')
            else:
                self.reply(400, b'{"error":true,"reason":"no recording for these coordinates"}', 'application/json')
            return
        if host == 'tiles.openfreemap.org' and url.path.startswith('/planet/') and url.path.endswith('.pbf'):
            # (C160) The vector tile over the map's middle (zoom 14, x 8681, y 4769), built by maptile.py.
            import maptile
            if url.path.endswith('/14/8681/4769.pbf'):
                self.reply(200, maptile.tile(), 'application/x-protobuf')
            else:
                self.reply(404, b'', 'text/plain')
            return
        if host == 'api.met.no' and url.path == '/weatherapi/metalerts/2.0/current.json':
            # (C156) MetAlerts for a point: a feature per alert in force whose resources name its CAP message. Written
            # from the documented shape, not captured; Oslo has a gale warning, any other point none.
            if query.get('lat', [''])[0] == '59.91':
                body = json.dumps({'type': 'FeatureCollection', 'features': [{'type': 'Feature', 'properties': {
                    'event': 'gale', 'severity': 'Moderate', 'area': 'Oslo',
                    'resources': [{'description': 'CAP file', 'mimeType': 'application/xml',
                                   'uri': 'https://api.met.no/weatherapi/metalerts/2.0/alert-oslo.cap'}]}}]})
            else:
                body = json.dumps({'type': 'FeatureCollection', 'features': []})
            self.reply(200, body.encode('utf-8'), 'application/json')
            return
        if host == 'api.met.no' and url.path == '/weatherapi/metalerts/2.0/alert-oslo.cap':
            self.reply(200, (here / 'alert-oslo.cap').read_bytes(), 'application/xml')
            return
        if host == 'geocoding-api.open-meteo.com' and url.path == '/v1/search':
            if query.get('name', [''])[0].lower() == 'bergen':
                self.reply(200, (here / 'geocode-bergen.json').read_bytes(), 'application/json')
            else:
                self.reply(200, b'{"generationtime_ms":0.1}', 'application/json')
            return
        if host == 'api.twelvedata.com' and url.path == '/symbol_search':
            # Public, no key: the recorded matches for "app", an empty list for anything else.
            if query.get('symbol', [''])[0].lower() == 'app':
                self.reply(200, (here / 'symbol_search-app.json').read_bytes(), 'application/json')
            else:
                self.reply(200, b'{"data":[],"status":"ok"}', 'application/json')
            return
        if host == 'www.alphavantage.co' and url.path == '/query' and query.get('function', [''])[0] == 'TIME_SERIES_DAILY':
            # The demo key serves IBM only; any other pair gets the "Information" notice the real service sends.
            if query.get('apikey', [''])[0] == 'demo' and query.get('symbol', [''])[0] == 'IBM':
                self.reply(200, (here / 'daily-IBM.json').read_bytes(), 'application/json')
            else:
                self.reply(200, b'{"Information":"The **demo** API key is for demo purposes only."}', 'application/json')
            return
        if host == 'api.polygon.io' and url.path.startswith('/v2/aggs/ticker/'):
            # No public key exists: the fixture key `polykey` and the symbol AAPL, the documented shape.
            if query.get('apiKey', [''])[0] != 'polykey':
                self.reply(401, b'{"status":"ERROR","request_id":"fixture","error":"Unknown API Key"}', 'application/json')
            elif url.path.split('/')[4] == 'AAPL':
                self.reply(200, (here / 'aggs-AAPL.json').read_bytes(), 'application/json')
            else:
                self.reply(200, b'{"ticker":"NONE","queryCount":0,"resultsCount":0,"adjusted":true,"status":"OK","request_id":"fixture","count":0}', 'application/json')
            return
        if host == 'api.twelvedata.com' and url.path == '/time_series':
            if query.get('apikey', [''])[0] != 'demo':
                self.reply(200, b'{"code":401,"message":"**apikey** parameter is incorrect or not specified.","status":"error"}', 'application/json')
                return
            known = here / ('time_series-%s.json' % query.get('symbol', [''])[0])
            if known.exists():
                self.reply(200, known.read_bytes(), 'application/json')
            else:
                self.reply(200, b'{"code":400,"message":"**symbol** not found","status":"error"}', 'application/json')
            return
        if host == 'neper.test' and url.path == '/translate':
            self.reply(200, translate(query.get('from', ['en'])[0], query.get('to', ['en'])[0], query.get('q', [''])[0]).encode('utf-8'), 'text/plain; charset=utf-8')
            return
        if host == 'neper.test' and url.path == '/pages/index.html':
            self.reply(200, PAGE_INDEX, 'text/html')
            return
        if host == 'neper.test' and url.path == '/pages/about.html':
            self.reply(200, PAGE_ABOUT, 'text/html')
            return
        if host == 'neper.test' and url.path == '/pages/old.html':
            # (C159) A moved page: a redirect the browser must follow.
            self.reply(302, b'', 'text/html', (('Location', '/pages/about.html'),))
            return
        if host == 'neper.test' and url.path == '/pages/form.html':
            self.reply(200, PAGE_FORM, 'text/html')
            return
        if host == 'neper.test' and url.path == '/pages/logo.svg':
            self.reply(200, LOGO_SVG, 'image/svg+xml')
            return
        if host == 'neper.test' and url.path == '/pages/report.bin':
            self.reply(200, REPORT_BIN, 'application/octet-stream')
            return
        if host == 'neper.test' and url.path == '/pages/echo.html':
            # (C159) What the form sent: the decoded fields, and a link to a download.
            fields = ', '.join('%s=%s' % (k, v[0]) for k, v in sorted(query.items()))
            page = ('<!doctype html><html><head><title>Echo</title></head><body><h1>Echo</h1>'
                    '<p>Query: %s</p><p><a href="/pages/report.bin">Download the report</a></p>'
                    '</body></html>' % fields).encode('utf-8')
            self.reply(200, page, 'text/html')
            return
        if host == 'neper.test' and url.path == '/pages/login.html':
            self.reply(200, PAGE_LOGIN, 'text/html',
                       (('Set-Cookie', 'sid=abc123; Path=/; Max-Age=3600; HttpOnly; Secure'),
                        ('Set-Cookie', 'theme=dark; Path=/pages')))
            return
        if host == 'neper.test' and url.path == '/pages/me.html':
            cookie = self.headers.get('Cookie') or ''
            page = ('<!doctype html><html><head><title>Account</title></head><body><h1>Account</h1>'
                    '<p>Cookie: %s</p></body></html>' % cookie).encode('utf-8')
            self.reply(200, page, 'text/html')
            return
        if host == 'neper.test' and url.path == '/v1/models':
            # (C171) The AI app's cheap key check: the model list, a 401 for the key `bad`.
            if self.headers.get('Authorization') == 'Bearer bad':
                self.reply(401, b'{"error":{"message":"bad key"}}', 'application/json')
            else:
                self.reply(200, b'{"object":"list","data":[{"id":"llama-7b"}]}', 'application/json')
            return
        if host == 'neper.test' and url.path.startswith('/range/'):
            # (C170) The Secure app's breach check by hash prefix (the k-anonymity range API): every suffix under the
            # prefix with a count, and for the prefix of a known password its real suffix.
            import hashlib
            prefix = url.path[len('/range/'):].upper()
            lines = []
            for n in range(6):
                suffix = hashlib.sha1(('decoy%s%d' % (prefix, n)).encode()).hexdigest().upper()[5:]
                lines.append('%s:%d' % (suffix, 1 + n))
            for known, count in (('hunter22', 24230577), ('correct-horse-battery', 7)):
                digest = hashlib.sha1(known.encode()).hexdigest().upper()
                if digest.startswith(prefix):
                    lines.append('%s:%d' % (digest[5:], count))
            self.reply(200, ('\r\n'.join(lines) + '\r\n').encode(), 'text/plain')
            return
        self.reply(200, BODY)

    def stream_chat(self, text):
        """(C171) The reply as a chunked text/event-stream of OpenAI-style deltas a moment apart, ended by [DONE]."""
        import json
        import time
        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream')
        self.send_header('Transfer-Encoding', 'chunked')
        self.send_header('Connection', 'close')
        self.end_headers()

        def chunk(data):
            self.wfile.write(('%x\r\n' % len(data)).encode() + data + b'\r\n')
            self.wfile.flush()
        words = text.split(' ')
        pieces = []
        step = max(1, len(words) // 4)
        for i in range(0, len(words), step):
            pieces.append(' '.join(words[i:i + step]) + ('' if i + step >= len(words) else ' '))
        chunk(b'data: ' + json.dumps({'choices': [{'index': 0, 'delta': {'role': 'assistant', 'content': ''}}]}).encode() + b'\n\n')
        for piece in pieces:
            time.sleep(0.7)
            chunk(b'data: ' + json.dumps({'choices': [{'index': 0, 'delta': {'content': piece}}]}).encode() + b'\n\n')
        chunk(b': keep-alive\n\n')
        chunk(b'data: [DONE]\n\n')
        self.wfile.write(b'0\r\n\r\n')
        self.wfile.flush()

    def do_POST(self):
        # (C141) The AI app's local model: an OpenAI-compatible chat endpoint. It answers with the last user
        # message it was sent (so the test sees the conversation reach the server), a 401 for the key `bad`.
        import json
        length = int(self.headers.get('Content-Length') or 0)
        raw = self.rfile.read(length)
        host = (self.headers.get('Host') or '').split(':')[0]
        # (C151) The Dynamic build server's routes (dynamic_services.py).
        if DYNAMIC is not None and DYNAMIC.post(self, host, self.path, raw):
            return
        # (C171) The AI app's providers (ai_services.py): the local model's OpenAI shape and the hosted three.
        if ai_services.post(self, host, self.path, raw):
        if WEB.post(self, host, self.path, raw):
            return
        if host == 'neper.test' and self.path == '/v1/chat/completions':
            if self.headers.get('Authorization') == 'Bearer bad':
                self.reply(401, b'{"error":{"message":"bad key"}}', 'application/json')
                return
            if self.headers.get('Authorization') == 'Bearer limit':
                self.reply(429, b'{"error":{"message":"rate limited"}}', 'application/json')
                return
            request = json.loads(raw.decode('utf-8'))
            messages = request.get('messages', [])
            last = ''
            for m in messages:
                if m.get('role') == 'user':
                    last = m.get('content', '')
            text = 'Echo from the neper test model (%d messages): %s' % (len(messages), last)
            if request.get('stream'):
                self.stream_chat(text)
                return
            answer = {'choices': [{'index': 0, 'message': {'role': 'assistant', 'content': text}, 'finish_reason': 'stop'}]}
            self.reply(200, json.dumps(answer).encode('utf-8'), 'application/json')
            return
        self.reply(404, b'{"error":"not found"}', 'application/json')

    def log_message(self, *args):
        pass


def dns():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.bind(('127.0.0.1', 5300))
    while True:
        data, peer = s.recvfrom(512)
        end = 12
        while data[end] != 0:
            end += data[end] + 1
        question = data[12:end + 5]
        header = data[:2] + b'\x81\x80' + struct.pack('>HHHH', 1, 1, 0, 0)
        answer = b'\xc0\x0c' + struct.pack('>HHIH', 1, 1, 60, 4) + bytes([10, 0, 2, 2])
        s.sendto(header + question + answer, peer)


def serve(port, secure):
    server = http.server.ThreadingHTTPServer(('127.0.0.1', port), Handler)
    if secure:
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.minimum_version = ssl.TLSVersion.TLSv1_3
        ctx.load_cert_chain(str(here / 'server.pem'), str(here / 'server.key'))
        server.socket = ctx.wrap_socket(server.socket, server_side=True)
    server.serve_forever()


def ssh_server():
    """TCP 8022: an SSH server (asyncssh) for the SSH app -- user neper, password secret, a shell that upper-cases
    each line and exits with status 7 on `exit`. Not started when asyncssh is not installed (NEPER_PYLIB names
    the directory that holds it)."""
    import asyncio
    import os
    sys.path.insert(0, os.environ.get('NEPER_PYLIB', 'D:/Temp/claude/pylib'))
    try:
        import asyncssh
    except ImportError:
        return

    class Server(asyncssh.SSHServer):
        def begin_auth(self, username):
            return True

        def password_auth_supported(self):
            return True

        def validate_password(self, username, password):
            return username == 'neper' and password == 'secret'

        # (C155) Any ed25519 key the user `neper` signs with is accepted: asyncssh checks the signature against the
        # key offered, so a login that gets through proves the client signed with the key it sent. The key itself is
        # said by the app on its console (ssh key public ...).
        def public_key_auth_supported(self):
            return True

        def validate_public_key(self, username, key):
            return username == 'neper'

    # (C155) The SFTP subsystem's root: a file and a folder with one in it, in a directory of its own.
    import tempfile
    sftp_root = tempfile.mkdtemp(prefix='neper-sftp-')
    with open(os.path.join(sftp_root, 'hello.txt'), 'wb') as f:
        f.write(b'hello from the sftp server\n')
    os.makedirs(os.path.join(sftp_root, 'docs'), exist_ok=True)
    with open(os.path.join(sftp_root, 'docs', 'readme.txt'), 'wb') as f:
        f.write(b'inside docs\n')

    class SortedSFTP(asyncssh.SFTPServer):
        """A listing in name order, so a fixture's taps do not depend on the host's directory order."""

        def listdir(self, path):
            return sorted(super().listdir(path))

    async def handle(process):
        process.stdout.write('ready\r\n$ ')
        buffer = ''
        while True:
            try:
                data = await process.stdin.read(1024)
            except asyncssh.TerminalSizeChanged:
                continue
            if not data:
                break
            buffer += data
            while '\r' in buffer:
                line, buffer = buffer.split('\r', 1)
                if line == 'exit':
                    process.exit(7)
                    return
                process.stdout.write(line.upper() + '\r\n$ ')

    async def main():
        # (C155) A fixed host key (ssh_host_ed25519, made once), so a client that trusted it on one boot finds it
        # again on the next; a fixture for a changed key seeds a different one on the client's side.
        fixed = here / 'ssh_host_ed25519'
        key = asyncssh.read_private_key(str(fixed)) if fixed.exists() else asyncssh.generate_private_key('ssh-ed25519')
        await asyncssh.create_server(Server, '127.0.0.1', 8022, server_host_keys=[key], process_factory=handle,
                                     sftp_factory=lambda chan: SortedSFTP(chan, chroot=os.fsencode(sftp_root)),
                                     encoding='utf-8', line_editor=False, kex_algs=['curve25519-sha256'],
                                     encryption_algs=['chacha20-poly1305@openssh.com'], mac_algs=['hmac-sha2-256'])
        await asyncio.Event().wait()

    asyncio.run(main())


for target in (dns, ssh_server, lambda: serve(8081, False), lambda: serve(8443, True)):
    threading.Thread(target=target, daemon=True).start()
import mail_services
mail_services.start()
import chat_services
chat_services.start(here)
if len(sys.argv) > 1:
    pathlib.Path(sys.argv[1]).write_text('ready')
threading.Event().wait()
