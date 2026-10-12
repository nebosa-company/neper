#!/usr/bin/env python3
"""Run the e.net.ssh fixture's client against a real SSH server (asyncssh) on loopback: password and public-key
authentication, a shell that upper-cases a line and exits with status 7, a wrong password, a changed host key.
Usage: drive.py CLIENT_EXE.  Set NEPER_PYLIB to a directory holding asyncssh.  Exit 0 when every mode passes."""
import asyncio
import os
import subprocess
import sys

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


async def run_client(exe, mode, port, host_key_hex):
    proc = await asyncio.create_subprocess_exec(exe, mode, str(port), host_key_hex)
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
    for mode, hex_key, want in (("password", key_bytes.hex(), 0), ("key", key_bytes.hex(), 0),
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
    return failed


if __name__ == "__main__":
    sys.exit(1 if asyncio.run(main(sys.argv[1])) else 0)
