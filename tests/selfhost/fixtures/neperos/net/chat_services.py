"""A small WebSocket chat server for the Chat app's fixture (C134), on loopback.

  TCP 8090  ws (plain), TCP 8453 wss (TLS 1.3, the HTTPS service's certificate)

Text frames carry one message each, fields separated by |:
  client -> server   JOIN|name              enters the chat
                     SAY|room|text          says something in a room
  server -> client   ROOM|room              a room that exists (after JOIN)
                     MSG|room|who|text      a message, the client's own echoed back and a scripted second person's
                                            reply ("Maya") to anything said in general

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


class Chat(socketserver.StreamRequestHandler):
    def send(self, text: str):
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
                self.send("MSG|%s|%s|%s" % (room, name, body))
                if room == "general":
                    # (C164) She types before she answers.
                    self.send("TYPING|general|Maya")
                    self.send("MSG|general|Maya|%s to you too" % body.split(" ")[0])



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


def start(here):
    plain = Server(("127.0.0.1", 8090), Chat)
    threading.Thread(target=plain.serve_forever, daemon=True).start()
    secure = Server(("127.0.0.1", 8453), Chat)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_3
    context.load_cert_chain(str(here / "server.pem"), str(here / "server.key"))
    secure.socket = context.wrap_socket(secure.socket, server_side=True)
    threading.Thread(target=secure.serve_forever, daemon=True).start()
