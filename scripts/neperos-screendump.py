#!/usr/bin/env python3
# (D2159, C108) Boot NeperOS with a virtio-gpu device, wait for the GPU driver server to flush its
# test pattern to the scanout, take a QMP screendump of the display, and print the screendump's
# byte count and SHA-256. The suite compares that SHA-256 to a golden; it is identical on QEMU 8.2
# (WSL) and 11.1 (Windows) because the pattern, the BGRA->RGB conversion and the PPM framing are
# all deterministic. Usage:
#   neperos-screendump.py <qemu> <kernel> <initrd> <out.ppm> [qmp-port]
import hashlib
import json
import os
import socket
import subprocess
import sys
import time


def qmp(sock, cmd):
    sock.sendall((json.dumps(cmd) + "\r\n").encode())
    buf = b""
    while True:
        chunk = sock.recv(65536)
        if not chunk:
            return None
        buf += chunk
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            line = line.strip()
            if not line:
                continue
            obj = json.loads(line)
            if "return" in obj or "error" in obj:
                return obj


def main():
    qemu, kernel, initrd, out_ppm = sys.argv[1:5]
    port = int(sys.argv[5]) if len(sys.argv) > 5 else 55123
    serial = out_ppm + ".serial"
    for stale in (serial, out_ppm):
        if os.path.exists(stale):
            os.remove(stale)
    args = [
        qemu, "-M", "virt,gic-version=3", "-cpu", "cortex-a76", "-m", "256M",
        "-nic", "none", "-no-reboot", "-display", "none",
        "-kernel", kernel, "-initrd", initrd, "-append", "gpu",
        "-device", "virtio-gpu-pci",
        "-serial", "file:" + serial,
        "-qmp", "tcp:127.0.0.1:%d,server,nowait" % port,
    ]
    proc = subprocess.Popen(args)
    try:
        sock = None
        deadline = time.time() + 20
        while time.time() < deadline and sock is None:
            try:
                sock = socket.create_connection(("127.0.0.1", port), timeout=1)
            except OSError:
                time.sleep(0.2)
        if sock is None:
            raise SystemExit("could not connect to QMP")
        sock.recv(65536)
        qmp(sock, {"execute": "qmp_capabilities"})
        deadline = time.time() + 60
        seen = False
        while time.time() < deadline and not seen:
            if os.path.exists(serial):
                with open(serial, "rb") as f:
                    if b"flushed" in f.read():
                        seen = True
            if not seen:
                time.sleep(0.2)
        if not seen:
            raise SystemExit("GPU driver did not flush in time")
        r = qmp(sock, {"execute": "screendump", "arguments": {"filename": out_ppm}})
        if r is None or "error" in r:
            raise SystemExit("screendump failed: %r" % r)
        with open(out_ppm, "rb") as f:
            data = f.read()
        print("bytes %d" % len(data))
        print("sha256 %s" % hashlib.sha256(data).hexdigest())
        try:
            qmp(sock, {"execute": "quit"})
        except OSError:
            pass
    finally:
        try:
            proc.wait(timeout=10)
        except Exception:
            proc.kill()


if __name__ == "__main__":
    main()
