"""The host side of the NeperOS network fixture (C117): everything the guest reaches at 10.0.2.2.

  python host_services.py [ready-file]

  UDP 5300  a DNS responder answering every A query with 10.0.2.2 (the guest names the resolver
            explicitly, so the fixture needs no internet and no privileged port)
  TCP 8081  HTTP
  TCP 8443  HTTPS, TLS 1.3 only, the leaf certificate signed by the fixture CA (names neper.test,
            api.exchange.coinbase.com, api.twelvedata.com, www.alphavantage.co, api.polygon.io); besides the plain
            page it answers the Stocks fixture's APIs from the recordings made by record.py

Writes the ready-file once all three listen, then serves until killed.
"""
import http.server
import pathlib
import socket
import ssl
import struct
import urllib.parse
import sys
import threading

here = pathlib.Path(__file__).resolve().parent
BODY = b'hello from the neper test server\n'


def recorded(name):
    return (here / name).read_bytes()


class Handler(http.server.BaseHTTPRequestHandler):
    def reply(self, status, body, kind='text/plain'):
        self.send_response(status)
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
        if host == 'api.exchange.coinbase.com' and url.path.startswith('/products/') and url.path.endswith('/candles'):
            product = url.path.split('/')[2]
            known = here / ('candles-%s.json' % product)
            if known.exists():
                self.reply(200, known.read_bytes(), 'application/json')
            else:
                self.reply(404, b'{"message":"NotFound"}', 'application/json')
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
        self.reply(200, BODY)

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


for target in (dns, lambda: serve(8081, False), lambda: serve(8443, True)):
    threading.Thread(target=target, daemon=True).start()
if len(sys.argv) > 1:
    pathlib.Path(sys.argv[1]).write_text('ready')
threading.Event().wait()
