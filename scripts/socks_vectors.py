"""Generate tests/selfhost/fixtures/link/net_socks/src/main.e (L121, D2521).

The oracle is PySocks, the reference SOCKS5 client.  Each scenario starts a scripted
server on loopback, lets PySocks connect through it and records every byte PySocks
sends and how it ends (success, SOCKS5Error with its code, SOCKS5AuthError,
GeneralProxyError, a closed connection).  The fixture replays the same scripted server
bytes into `e.net.socks` over slice readers and writers and requires the same request
bytes and the same class of outcome.  UDP datagram headers are checked the same way
from PySocks `sendto` and `recvfrom`.  Install with
`python -m pip install --target DIR PySocks` and run with PYLIBS=DIR.
"""
import os
import socket
import struct
import sys
import threading
from pathlib import Path

sys.path.insert(0, os.environ.get('PYLIBS', ''))
import socks  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'tests/selfhost/fixtures/link/net_socks/src/main.e'


def esc(data):
    out = []
    for b in data:
        if 48 <= b <= 57 or 65 <= b <= 90 or 97 <= b <= 122 or b in b'.-_':
            out.append(chr(b))
        else:
            out.append('\\x%02x' % b)
    return '"' + ''.join(out) + '"'


def recvn(conn, n):
    data = b''
    while len(data) < n:
        chunk = conn.recv(n - len(data))
        if not chunk:
            raise EOFError
        data += chunk
    return data


def run_tcp(user, password, host, port, method, auth, final):
    """One PySocks CONNECT against a scripted server; returns (client bytes, outcome)."""
    srv = socket.socket()
    srv.bind(('127.0.0.1', 0))
    srv.listen(1)
    seen = bytearray()

    def serve():
        conn, _ = srv.accept()
        conn.settimeout(2)
        try:
            greeting = recvn(conn, 2)
            greeting += recvn(conn, greeting[1])
            seen.extend(greeting)
            conn.sendall(method)
            if auth is not None:
                head = recvn(conn, 2)
                name = recvn(conn, head[1])
                plen = recvn(conn, 1)
                word = recvn(conn, plen[0])
                seen.extend(head + name + plen + word)
                conn.sendall(auth)
            if final is not None:
                head = recvn(conn, 4)
                seen.extend(head)
                if head[3] == 1:
                    rest = recvn(conn, 6)
                elif head[3] == 4:
                    rest = recvn(conn, 18)
                else:
                    length = recvn(conn, 1)
                    rest = length + recvn(conn, length[0] + 2)
                seen.extend(rest)
                conn.sendall(final)
            conn.settimeout(0.3)
            try:
                conn.recv(1)
            except OSError:
                pass
        except (EOFError, OSError):
            pass
        finally:
            conn.close()

    thread = threading.Thread(target=serve, daemon=True)
    thread.start()
    client = socks.socksocket()
    client.settimeout(3)
    client.set_proxy(socks.SOCKS5, '127.0.0.1', srv.getsockname()[1], True, user, password)
    outcome = 'ok'
    try:
        client.connect((host, port))
    except socks.ProxyError as e:
        # PySocks wraps every protocol failure as "Socket error: <reason>" (the classes are
        # OSError subclasses), so the reason text is what tells the outcomes apart.
        text = str(e)
        if text.startswith('Socket error: 0x'):
            outcome = 'rejected:' + text.split(':')[1].strip()
        elif 'rejected' in text:
            outcome = 'unsupported'
        elif 'authentication failed' in text or 'No username/password' in text:
            outcome = 'authfailed'
        elif 'closed unexpectedly' in text:
            outcome = 'closed'
        else:
            outcome = 'protocol'
    finally:
        client.close()
        thread.join()
        srv.close()
    return bytes(seen), outcome


lines = []
code = [30]


def check(expr):
    lines.append('    if !(%s) { os.exit(%di32) }' % (expr, code[0]))
    code[0] += 1
    if code[0] > 250:
        raise SystemExit('too many checks')


ERRORS = {'ok': 0, 'rejected': 1, 'authfailed': 2, 'unsupported': 3, 'protocol': 4, 'closed': 5}


def tcp_case(user, password, host, port, method, auth, final, address=None):
    request, outcome = run_tcp(user, password, host, port, method, auth, final)
    rejected = 0
    if outcome.startswith('rejected'):
        rejected = int(outcome.split(':')[1], 16) if outcome.split(':')[1].startswith('0x') else 0
        outcome = 'rejected'
    replies = method + (auth or b'') + (final or b'')
    # a refused CONNECT: the code is the second byte of the final reply
    if outcome == 'rejected' and final is not None:
        rejected = final[1]
    kind = 0
    ip = b''
    if address is not None:
        ip = socket.inet_aton(address) if ':' not in address else socket.inet_pton(socket.AF_INET6, address)
        kind = 1 if len(ip) == 4 else 2
    # expected bound address of a successful reply
    atyp = final[3] if outcome == 'ok' else 0
    bound = b''
    bport = 0
    if outcome == 'ok':
        if atyp == 1:
            bound, bport = final[4:8], struct.unpack('>H', final[8:10])[0]
        elif atyp == 4:
            bound, bport = final[4:20], struct.unpack('>H', final[20:22])[0]
        else:
            n = final[4]
            bound, bport = final[5:5 + n], struct.unpack('>H', final[5 + n:7 + n])[0]
    check('scenario(%du8, %s, %s, %s, %du16, %s, %s, %s, %du8, %du8, %du8, %s, %du16)' % (
        kind, esc((user or '').encode()), esc((password or '').encode()), esc(host.encode()) if not address else '""',
        port, esc(ip), esc(replies), esc(request), ERRORS[outcome], rejected, atyp, esc(bound), bport))
    return outcome


ok4 = b'\x05\x00\x00\x01\x0a\x00\x00\x01\x1f\x90'
ok6 = b'\x05\x00\x00\x04' + bytes(15) + b'\x01\x00\x50'
okd = b'\x05\x00\x00\x03\x0bproxy.local\x01\xbb'
NONE = b'\x05\x00'
PASS = b'\x05\x02'

tcp_case(None, None, 'example.com', 80, NONE, None, ok4)
tcp_case('alice', 's3cret', 'example.com', 443, PASS, b'\x01\x00', okd)
tcp_case(None, None, '93.184.216.34', 443, NONE, None, ok6, address='93.184.216.34')
tcp_case(None, None, '2001:db8::1', 80, NONE, None, ok4, address='2001:db8::1')
tcp_case('alice', 's3cret', '10.1.2.3', 25, PASS, b'\x01\x00', okd, address='10.1.2.3')
# PySocks encodes the length as chr(n).encode(), wrong from 128 up, so it is the oracle to 127
# and the 255-byte limit of RFC 1928 section 5 is written out by hand.
tcp_case(None, None, '.'.join(['a' * 63, 'b' * 63]), 1, NONE, None, ok4)
name255 = '.'.join(['a' * 63] * 3 + ['a' * 62 + 'b']).encode()
assert len(name255) == 255
check('scenario(0u8, "", "", %s, 1u16, "", %s, %s, 0u8, 0u8, 1u8, %s, 8080u16)' % (
    esc(name255), esc(NONE + ok4),
    esc(bytes([5, 1, 0, 5, 1, 0, 3, 255]) + name255 + bytes([0, 1])), esc(ok4[4:8])))
check('scenario(0u8, %s, %s, "example.com", 8080u16, "", %s, %s, 0u8, 0u8, 1u8, %s, 8080u16)' % (
    esc(b'u' * 255), esc(b'p' * 255), esc(PASS + b'\x01\x00' + ok4),
    esc(bytes([5, 2, 0, 2, 1, 255]) + b'u' * 255 + bytes([255]) + b'p' * 255 +
        bytes([5, 1, 0, 3, 11]) + b'example.com' + struct.pack('>H', 8080)), esc(ok4[4:8])))
for rep in range(1, 9):
    tcp_case(None, None, 'example.com', 80, NONE, None, b'\x05' + bytes([rep]) + b'\x00\x01\x00\x00\x00\x00\x00\x00')
tcp_case(None, None, 'example.com', 80, b'\x05\xff', None, None)
tcp_case('alice', 's3cret', 'example.com', 80, PASS, b'\x01\x01', None)
tcp_case(None, None, 'example.com', 80, b'\x04\x00', None, None)
tcp_case(None, None, 'example.com', 80, PASS, None, None)
tcp_case('alice', 's3cret', 'example.com', 80, b'\x05\x03', None, None)
tcp_case('alice', 's3cret', 'example.com', 80, PASS, b'\x05\x00', None)
tcp_case(None, None, 'example.com', 80, NONE, None, b'\x05\x00\x00\x09\x01\x02\x03\x04\x00\x50')
tcp_case(None, None, 'example.com', 80, NONE, None, b'\x04\x00\x00\x01\x01\x02\x03\x04\x00\x50')
tcp_case(None, None, 'example.com', 80, NONE, None, b'\x05\x00\x00\x01\x0a')
tcp_case(None, None, 'example.com', 80, NONE, None, b'\x05\x00\x00\x03\x20abc')
tcp_case(None, None, 'example.com', 80, b'\x05', None, None)

# --- UDP datagram headers: PySocks sendto (encode) and recvfrom (decode).


def run_udp(destinations, replies):
    srv = socket.socket()
    srv.bind(('127.0.0.1', 0))
    srv.listen(1)
    relay = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    relay.bind(('127.0.0.1', 0))
    relay.settimeout(3)
    sent = []
    results = []

    def serve():
        conn, _ = srv.accept()
        conn.settimeout(3)
        try:
            greeting = recvn(conn, 2)
            recvn(conn, greeting[1])
            conn.sendall(b'\x05\x00')
            head = recvn(conn, 4)
            if head[3] == 3:
                length = recvn(conn, 1)
                recvn(conn, length[0] + 2)
            elif head[3] == 1:
                recvn(conn, 6)
            else:
                recvn(conn, 18)
            conn.sendall(b'\x05\x00\x00\x01\x7f\x00\x00\x01' + struct.pack('>H', relay.getsockname()[1]))
            addr = None
            for _ in destinations:
                data, addr = relay.recvfrom(4096)
                sent.append(data)
            for datagram in replies:
                relay.sendto(datagram, addr)
            conn.settimeout(0.5)
            try:
                conn.recv(1)
            except OSError:
                pass
        except (EOFError, OSError):
            pass
        finally:
            conn.close()

    thread = threading.Thread(target=serve, daemon=True)
    thread.start()
    client = socks.socksocket(socket.AF_INET, socket.SOCK_DGRAM)
    client.set_proxy(socks.SOCKS5, '127.0.0.1', srv.getsockname()[1])
    client.settimeout(2)
    for dest, payload in destinations:
        client.sendto(payload, dest)
    for _ in replies:
        try:
            results.append(('ok',) + client.recvfrom(4096))
        except Exception as e:  # noqa: BLE001
            results.append(('error', type(e).__name__))
    client.close()
    thread.join()
    srv.close()
    relay.close()
    return sent, results


dests = [(('example.com', 53), b'ping'), (('1.2.3.4', 5353), b'\x00\xff\x01'), (('2001:db8::7', 9), b'v6'), (('example.com', 1), b'')]
v6 = socket.inet_pton(socket.AF_INET6, '2001:db8::7')
replies = [
    b'\x00\x00\x00\x01\x01\x02\x03\x04\x00\x35pong',
    b'\x00\x00\x00\x03\x07example\x01\xbbhey',
    b'\x00\x00\x00\x04' + v6 + b'\x23\x28' + b'six',
    b'\x00\x00\x00\x01\x09\x09\x09\x09\x00\x01',
    b'\x00\x00\x01\x01\x01\x02\x03\x04\x00\x35frag',
    b'\x00\x00\x00\x09\x01\x02\x03\x04\x00\x35bad',
]
sent, results = run_udp(dests, replies)
assert len(sent) == len(dests), sent
for (dest, payload), datagram in zip(dests, sent):
    host, port = dest
    if host == 'example.com':
        check('udp_encode_domain_ok(%s, %du16, %s, %s)' % (esc(host.encode()), port, esc(payload), esc(datagram)))
    else:
        ip = socket.inet_aton(host) if ':' not in host else socket.inet_pton(socket.AF_INET6, host)
        check('udp_encode_ok(%s, %du16, %s, %s)' % (esc(ip), port, esc(payload), esc(datagram)))
for datagram, result in zip(replies, results):
    if result[0] == 'ok':
        data, addr = result[1], result[2]
        host, port = addr
        if isinstance(host, bytes):
            check('udp_decode_name(%s, %s, %du16, %s)' % (esc(datagram), esc(host), port, esc(data)))
        else:
            ip = socket.inet_aton(host) if ':' not in host else socket.inet_pton(socket.AF_INET6, host)
            check('udp_decode_ok(%s, %s, %du16, %s)' % (esc(datagram), esc(ip), port, esc(data)))
    else:
        check('udp_decode_refused(%s)' % esc(datagram))
check('udp_decode_refused(%s)' % esc(b'\x00\x00\x00\x01\x01\x02'))
check('udp_decode_refused(%s)' % esc(b'\x00'))
check('udp_decode_refused(%s)' % esc(b'\x01\x00\x00\x01\x01\x02\x03\x04\x00\x35'))
check('udp_decode_refused(%s)' % esc(b'\x00\x00\x00\x03\x09ab'))

body = '\n'.join(lines)
TEMPLATE = (ROOT / 'scripts' / 'socks_fixture_head.e').read_text(encoding='utf-8')
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(TEMPLATE.replace('@@CHECKS@@', body).replace('@@LONG@@', 'a' * 300), encoding='utf-8', newline='\n')
print('wrote', OUT, 'checks', code[0] - 30)
print('udp results', results)
