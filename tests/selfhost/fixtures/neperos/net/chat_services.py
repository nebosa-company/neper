"""A small WebSocket chat server for the Chat app's fixture (C134), on loopback.

  TCP 8090  ws (plain), TCP 8453 wss (TLS 1.3, the HTTPS service's certificate)

Text frames carry one message each, fields separated by |:
  client -> server   JOIN|name              enters the chat
                     SAY|room|text          says something in a room
  server -> client   ROOM|room              a room that exists (after JOIN)
                     MSG|room|who|text      a message, the client's own echoed back and a scripted second person's
                                            reply ("Maya") to anything said in general

(C164) The server is a hub: every client connected hears every message, and a second client of its own is one of them.
  client -> server   JOIN|name|secret       enters as an account (sam/samsecret, noor/noorsecret, neper/neper); a wrong
                                            secret is answered AUTH|bad and the connection ends, a right one AUTH|ok|name
                     SAYTO|room|id|text     says something in a room as a reply to message `id`
                     REACT|room|id|emoji    toggles the sender's reaction to message `id`
  server -> client   MID|room|id|who|reply  follows every MSG: the message's id (and the id it replies to, 0 for none)
                     REACT|room|id|who|emoji|count   the reaction counted, to everyone
  The scripted second client ("noor", a real connection to this server made by `start`) reacts to every message the
  account `sam` says and answers it with a reply in its thread.

The guest reaches it at 10.0.2.2 (neper.test). The upgrade and the frames are written here by hand so the fixture needs
nothing but the standard library.
"""
import base64
import hashlib
import socketserver
import ssl
import struct
import threading

GUID = b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
LOG = []
LOCK = threading.Lock()
ACCOUNTS = {"sam": "samsecret", "noor": "noorsecret", "neper": "neper"}
CLIENTS = []
MESSAGES = {}
REACTIONS = {}
NEXT_ID = [1]


def broadcast(text: str):
    with LOCK:
        targets = list(CLIENTS)
    for client in targets:
        try:
            client.send(text)
        except OSError:
            pass


def frame(payload: bytes, opcode: int = 1) -> bytes:
    n = len(payload)
    if n < 126:
        return bytes([0x80 | opcode, n]) + payload
    return bytes([0x80 | opcode, 126]) + struct.pack(">H", n) + payload


def read_frame(rfile):
    head = rfile.read(2)
    if len(head) < 2:
        return None, b""
    opcode = head[0] & 0x0F
    n = head[1] & 0x7F
    masked = head[1] & 0x80
    if n == 126:
        n = struct.unpack(">H", rfile.read(2))[0]
    elif n == 127:
        n = struct.unpack(">Q", rfile.read(8))[0]
    mask = rfile.read(4) if masked else b""
    data = rfile.read(n)
    if masked:
        data = bytes(b ^ mask[i % 4] for i, b in enumerate(data))
    return opcode, data


SEND_LOCK = threading.Lock()


class Chat(socketserver.StreamRequestHandler):
    def send(self, text: str):
        # One frame at a time on every connection: a broadcast comes from another client's thread.
        with SEND_LOCK:
            self.wfile.write(frame(text.encode()))
            self.wfile.flush()

    def handle(self):
        request = b""
        while not request.endswith(b"\r\n\r\n"):
            chunk = self.rfile.readline()
            if not chunk:
                return
            request += chunk
        path = request.split(b" ", 2)[1].decode() if b" " in request else "/"
        key = b""
        for line in request.split(b"\r\n"):
            if line.lower().startswith(b"sec-websocket-key:"):
                key = line.split(b":", 1)[1].strip()
        accept = base64.b64encode(hashlib.sha1(key + GUID).digest())
        self.wfile.write(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                         b"Sec-WebSocket-Accept: " + accept + b"\r\n\r\n")
        self.wfile.flush()
        if path.startswith("/meet"):
            self.meeting()
            return
        name = "guest"
        while True:
            opcode, data = read_frame(self.rfile)
            if opcode is None or opcode == 8:
                return
            if opcode != 1:
                continue
            text = data.decode("utf-8", "replace")
            parts = text.split("|", 2)
            if parts[0] == "JOIN" and len(parts) > 1:
                name = parts[1]
                if len(parts) == 3:
                    # (C164) An account: the secret has to be the one the server holds.
                    if ACCOUNTS.get(name) != parts[2]:
                        self.send("AUTH|bad")
                        return
                    self.send("AUTH|ok|" + name)
                with LOCK:
                    CLIENTS.append(self)
                for room in ("general", "design", "builds"):
                    self.send("ROOM|" + room)
                # (C164) Who is online.
                self.send("PRESENCE|Maya|online")
                with LOCK:
                    LOG.append(("join", name))
            elif parts[0] == "SAY" and len(parts) == 3:
                room, body = parts[1], parts[2]
                with LOCK:
                    LOG.append(("say", name, room, body))
                self.said(room, name, body, 0)
                if room == "general":
                    # (C164) She types before she answers.
                    self.send("TYPING|general|Maya")
                    broadcast("MSG|general|Maya|%s to you too" % body.split(" ")[0])
            elif parts[0] == "SAYTO" and len(parts) == 3:
                room, rest = parts[1], parts[2]
                reply, _, body = rest.partition("|")
                self.said(room, name, body, int(reply) if reply.isdigit() else 0)
            elif parts[0] == "REACT" and len(parts) == 3:
                room = parts[1]
                ident, _, emoji = parts[2].partition("|")
                key = (room, ident, emoji)
                with LOCK:
                    holders = REACTIONS.setdefault(key, set())
                    if name in holders:
                        holders.discard(name)
                    else:
                        holders.add(name)
                    count = len(holders)
                broadcast("REACT|%s|%s|%s|%s|%d" % (room, ident, name, emoji, count))

    def said(self, room, who, body, reply):
        """One message from `who`: numbered, heard by every client (MSG for the older clients, MID with its id)."""
        with LOCK:
            ident = NEXT_ID[0]
            NEXT_ID[0] += 1
            MESSAGES[ident] = (room, who, body, reply)
        broadcast("MSG|%s|%s|%s" % (room, who, body))
        broadcast("MID|%s|%d|%s|%d" % (room, ident, who, reply))

    def finish(self):
        with LOCK:
            if self in CLIENTS:
                CLIENTS.remove(self)
        super().finish()



def meeting(self):
    """A meeting: JOIN|name|title is answered with the others in it (Maya, Alex) and then a speaker every half
    second; MUTE|n, HAND|n and BYE are acknowledged."""
    done = threading.Event()

    def speakers():
        order = ["Maya", "Alex", "Maya", "Alex", "Maya", "Alex", "Maya", "Alex", "Maya", "Alex", "Maya", "Alex"]
        for who in order:
            if done.wait(0.5):
                return
            try:
                self.send("SPEAK|" + who)
            except OSError:
                return

    while True:
        opcode, data = read_frame(self.rfile)
        if opcode is None or opcode == 8:
            done.set()
            return
        if opcode != 1:
            continue
        parts = data.decode("utf-8", "replace").split("|")
        if parts[0] == "JOIN":
            self.send("PEER|Maya")
            self.send("PEER|Alex")
            threading.Thread(target=speakers, daemon=True).start()
        elif parts[0] in ("MUTE", "HAND"):
            self.send("ACK|%s|%s" % (parts[0].lower(), parts[1] if len(parts) > 1 else ""))
        elif parts[0] == "BYE":
            self.send("ACK|bye|")
            done.set()
            return


Chat.meeting = meeting


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def noor():
    """(C164) The second client: a real connection to this server that joins as `noor` and, to every message `sam`
    says, adds a +1 and a reply in its thread."""
    import socket
    import time
    for _ in range(50):
        try:
            link = socket.create_connection(("127.0.0.1", 8090), timeout=5)
            break
        except OSError:
            time.sleep(0.1)
    else:
        return
    key = base64.b64encode(b"noor-client-key!!")
    link.sendall(b"GET /chat HTTP/1.1\r\nHost: neper.test\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                 b"Sec-WebSocket-Key: " + key + b"\r\nSec-WebSocket-Version: 13\r\n\r\n")
    reader = link.makefile("rb")
    while True:
        line = reader.readline()
        if not line or line == b"\r\n":
            break

    def say(text):
        # A client frame is masked; the key of zeros leaves the payload as it is.
        payload = text.encode()
        head = bytes([0x81, 0x80 | len(payload)]) + b"\x00\x00\x00\x00"
        with SEND_LOCK:
            link.sendall(head + payload)
    say("JOIN|noor|noorsecret")
    last = {}
    while True:
        opcode, data = read_frame(reader)
        if opcode is None or opcode == 8:
            return
        fields = data.decode("utf-8", "replace").split("|", 4)
        if fields[0] == "MID" and len(fields) >= 5 and fields[3] == "sam":
            room, ident = fields[1], fields[2]
            time.sleep(0.5)
            say("REACT|%s|%s|+1" % (room, ident))
            say("SAYTO|%s|%s|noted" % (room, ident))


def start(here):
    plain = Server(("127.0.0.1", 8090), Chat)
    threading.Thread(target=plain.serve_forever, daemon=True).start()
    threading.Thread(target=noor, daemon=True).start()
    secure = Server(("127.0.0.1", 8453), Chat)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_3
    context.load_cert_chain(str(here / "server.pem"), str(here / "server.key"))
    secure.socket = context.wrap_socket(secure.socket, server_side=True)
    threading.Thread(target=secure.serve_forever, daemon=True).start()
