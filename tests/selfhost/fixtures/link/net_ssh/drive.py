#!/usr/bin/env python3
"""Run the e.net.ssh fixture's client against a real SSH server (asyncssh) on loopback: password and public-key
authentication, a shell that upper-cases a line and exits with status 7, a wrong password, a changed host key.
Usage: drive.py CLIENT_EXE.  Set NEPER_PYLIB to a directory holding asyncssh.  Exit 0 when every mode passes."""
import asyncio
import os
import subprocess
import sys
import tempfile

sys.path.insert(0, os.environ.get("NEPER_PYLIB", "D:/Temp/claude/pylib"))
import asyncssh  # noqa: E402
from cryptography.hazmat.primitives import serialization  # noqa: E402
from cryptography.hazmat.primitives.asymmetric import ed25519  # noqa: E402

SEED = bytes(range(1, 33))  # the client's key, as the fixture derives it


def private_key_from_seed(seed: bytes) -> asyncssh.SSHKey:
    key = ed25519.Ed25519PrivateKey.from_private_bytes(seed)
    pem = key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.OpenSSH, serialization.NoEncryption())
    return asyncssh.import_private_key(pem)


class Server(asyncssh.SSHServer):
    def begin_auth(self, username):
        return True

    def password_auth_supported(self):
        return True

    def validate_password(self, username, password):
        return username == "neper" and password == "secret"

    def public_key_auth_supported(self):
        return True

    def validate_public_key(self, username, key):
        return username == "neper" and key.get_fingerprint() == CLIENT_KEY.get_fingerprint()


async def handle(process):
    process.stdout.write("ready\r\n$ ")
    buffer = ""
    while True:
        try:
            data = await process.stdin.read(1024)
        except asyncssh.TerminalSizeChanged:
            continue
        if not data:
            break
        buffer += data
        while "\r" in buffer:
            line, buffer = buffer.split("\r", 1)
            if line == "exit":
                process.exit(7)
                return
            process.stdout.write(line.upper() + "\r\n$ ")


CLIENT_KEY = private_key_from_seed(SEED)


class ForwardServer(Server):
    """(C155) A server that also takes `direct-tcpip` channels: asyncssh connects to the target itself."""

    def connection_requested(self, dest_host, dest_port, orig_host, orig_port):
        return True


async def run_client(exe, mode, port, host_key_hex, *extra):
    proc = await asyncio.create_subprocess_exec(exe, mode, str(port), host_key_hex, *[str(x) for x in extra])
    try:
        await asyncio.wait_for(proc.wait(), 60)
    except asyncio.TimeoutError:
        proc.kill()
        return -1
    return proc.returncode


async def main(exe):
    host_key = asyncssh.generate_private_key("ssh-ed25519")
    other_key = asyncssh.generate_private_key("ssh-ed25519")
    server = await asyncssh.create_server(
        Server, "127.0.0.1", 0, server_host_keys=[host_key], process_factory=handle,
        encoding="utf-8", line_editor=False, kex_algs=["curve25519-sha256"],
        encryption_algs=["chacha20-poly1305@openssh.com"], mac_algs=["hmac-sha2-256"])
    port = server.sockets[0].getsockname()[1]
    public_raw = host_key.public_data  # the SSH blob: string type, string key
    key_bytes = public_raw[-32:]
    wrong_bytes = other_key.public_data[-32:]
    failed = 0
    for mode, hex_key, want in (("password", key_bytes.hex(), 0), ("early", key_bytes.hex(), 0), ("key", key_bytes.hex(), 0),
                                ("badpass", key_bytes.hex(), 0), ("badhost", wrong_bytes.hex(), 0)):
        code = await run_client(exe, mode, port, hex_key)
        print("net_ssh %s: exit %s" % (mode, code))
        if code != want:
            failed += 1
    server.close()
    await server.wait_closed()
    # (C155) The other ciphers, and a key exchange begun by the server in the middle of the session (its byte limit
    # set low): each against a server that has only that cipher.
    for mode, cipher_name, extra in (("gcm256", "aes256-gcm@openssh.com", {}), ("gcm128", "aes128-gcm@openssh.com", {}),
                                     ("rekey", "aes256-gcm@openssh.com", {"rekey_bytes": 1500})):
        other_server = await asyncssh.create_server(
            Server, "127.0.0.1", 0, server_host_keys=[host_key], process_factory=handle,
            encoding="utf-8", line_editor=False, kex_algs=["curve25519-sha256"],
            encryption_algs=[cipher_name], mac_algs=["hmac-sha2-256"], **extra)
        other_port = other_server.sockets[0].getsockname()[1]
        code = await run_client(exe, mode, other_port, key_bytes.hex())
        print("net_ssh %s: exit %s" % (mode, code))
        if code != 0:
            failed += 1
        other_server.close()
        await other_server.wait_closed()
    # (C155) The sftp subsystem, with a chroot holding hello.txt (the client reads it and writes up.bin, which is
    # checked here against what it should hold), and direct-tcpip forwards: to an echo server that upper-cases a
    # line, and to a port nothing listens on (refused).
    with tempfile.TemporaryDirectory() as root:
        with open(os.path.join(root, "hello.txt"), "wb") as f:
            f.write(b"hello sftp\n")
        sftp_server = await asyncssh.create_server(
            Server, "127.0.0.1", 0, server_host_keys=[host_key], process_factory=handle,
            sftp_factory=lambda chan: asyncssh.SFTPServer(chan, chroot=os.fsencode(root)),
            encoding="utf-8", line_editor=False, kex_algs=["curve25519-sha256"],
            encryption_algs=["chacha20-poly1305@openssh.com"], mac_algs=["hmac-sha2-256"])
        sftp_port = sftp_server.sockets[0].getsockname()[1]
        code = await run_client(exe, "sftp", sftp_port, key_bytes.hex())
        written = open(os.path.join(root, "up.bin"), "rb").read() if os.path.exists(os.path.join(root, "up.bin")) else b""
        print("net_ssh sftp: exit %s, up.bin %d bytes %s" % (code, len(written), "ok" if written == bytes(range(200)) else "WRONG"))
        if code != 0 or written != bytes(range(200)):
            failed += 1
        sftp_server.close()
        await sftp_server.wait_closed()

    async def echo(reader, writer):
        data = await reader.readline()
        writer.write(data.upper())
        await writer.drain()
        writer.close()
    echo_server = await asyncio.start_server(echo, "127.0.0.1", 0)
    echo_port = echo_server.sockets[0].getsockname()[1]
    closed = await asyncio.start_server(echo, "127.0.0.1", 0)
    closed_port = closed.sockets[0].getsockname()[1]
    closed.close()
    await closed.wait_closed()
    forward_server = await asyncssh.create_server(
        ForwardServer, "127.0.0.1", 0, server_host_keys=[host_key], process_factory=handle,
        encoding="utf-8", line_editor=False, kex_algs=["curve25519-sha256"],
        encryption_algs=["chacha20-poly1305@openssh.com"], mac_algs=["hmac-sha2-256"])
    forward_port = forward_server.sockets[0].getsockname()[1]
    for mode, target in (("forward", echo_port), ("forward_refused", closed_port)):
        code = await run_client(exe, mode, forward_port, key_bytes.hex(), target)
        print("net_ssh %s: exit %s" % (mode, code))
        if code != 0:
            failed += 1
    forward_server.close()
    await forward_server.wait_closed()
    echo_server.close()
    return failed


if __name__ == "__main__":
    sys.exit(1 if asyncio.run(main(sys.argv[1])) else 0)
