#!/usr/bin/env python3
# (D2160, C109) Boot NeperOS with a virtio-input device, wait for the input server to come up, inject
# a key or a tap through QMP input-send-event, and print the serial transcript (the client prints
# each event it receives from the server over IPC). Usage:
#   neperos-input.py <qemu> <kernel> <archive> <keyboard|tablet> <serial.out> [qmp-port]
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


def serial_text(path):
    if not os.path.exists(path):
        return ""
    with open(path, "rb") as f:
        return f.read().decode("latin-1")


def wait_for(path, needle, timeout):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if needle in serial_text(path):
            return True
        time.sleep(0.2)
    return False


def main():
    qemu, kernel, archive, device, serial = sys.argv[1:6]
    port = int(sys.argv[6]) if len(sys.argv) > 6 else 55130
    # The boot mode: `input` (the input server + client, C109) or `compositor` (the compositor routes
    # input to the focused app, C110), which also needs the display device.
    append = sys.argv[7] if len(sys.argv) > 7 else "input"
    # The serial line that marks the run complete (default per boot mode); a caller whose client
    # prints something else (e.g. the tap-launch launcher) passes its own.
    done_needle = sys.argv[8] if len(sys.argv) > 8 else ("app done" if "compositor" in append.split() else "input client done")
    if os.path.exists(serial):
        os.remove(serial)
    dev = "virtio-keyboard-pci" if device == "keyboard" else "virtio-tablet-pci"
    args = [
        qemu, "-M", "virt,gic-version=3", "-cpu", "cortex-a76", "-m", "256M",
        "-nic", "none", "-no-reboot", "-display", "none",
        "-kernel", kernel, "-initrd", archive, "-append", append,
        "-device", dev,
        "-serial", "file:" + serial,
        "-qmp", "tcp:127.0.0.1:%d,server,nowait" % port,
    ]
    if "compositor" in append.split():
        args[args.index("-device"):args.index("-device")] = ["-device", "virtio-gpu-pci"]
    # An optional raw disk image (argv[9]) behind a virtio-blk device, for the unified shell's
    # filesystem wallpaper (D2196).
    if len(sys.argv) > 9:
        args += ["-drive", "file=%s,format=raw,if=none,id=blk0" % sys.argv[9],
                 "-device", "virtio-blk-pci,disable-legacy=on,drive=blk0"]
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
        if not wait_for(serial, "input ready", 60):
            raise SystemExit("input server not ready")
        if device == "keyboard":
            qmp(sock, {"execute": "input-send-event", "arguments": {"events": [
                {"type": "key", "data": {"down": True, "key": {"type": "qcode", "data": "a"}}}]}})
            qmp(sock, {"execute": "input-send-event", "arguments": {"events": [
                {"type": "key", "data": {"down": False, "key": {"type": "qcode", "data": "a"}}}]}})
        else:
            qmp(sock, {"execute": "input-send-event", "arguments": {"events": [
                {"type": "abs", "data": {"axis": "x", "value": 16384}},
                {"type": "abs", "data": {"axis": "y", "value": 16384}},
                {"type": "btn", "data": {"down": True, "button": "left"}}]}})
            qmp(sock, {"execute": "input-send-event", "arguments": {"events": [
                {"type": "btn", "data": {"down": False, "button": "left"}}]}})
        wait_for(serial, done_needle, 20)
        sys.stdout.write(serial_text(serial))
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
