#!/usr/bin/env python3
"""The files a seeded fixture's disk starts with (liveseedfixture rows of tests/selfhost/neperos-apps.txt).

  make_fixture_seed.py <fixture> <out-dir>   writes the files and prints one `/path=file` argument per line, for
                                             scripts/make_fs_image.py

secure_breach  /breachhost            the host Secure asks for the breach range API (the test boot's neper.test)
ssh_changed    /ssh/known             the SSH app trusts a key for slot 5 (neper-test) that is not the server's
"""
import pathlib
import sys


def main():
    name, out = sys.argv[1], pathlib.Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    files = {}
    if name == 'secure_breach':
        files['/breachhost'] = b'neper.test\n'
    elif name == 'ssh_changed':
        # eight trusted flags, then eight 32-byte keys: slot 5 is trusted with a key of 0xAB bytes.
        flags = bytearray(8)
        flags[5] = 1
        keys = bytearray(256)
        keys[5 * 32:6 * 32] = bytes([0xAB]) * 32
        files['/ssh/known'] = bytes(flags + keys)
    else:
        raise SystemExit('no seed for ' + name)
    for path, data in files.items():
        local = out / (name + path.replace('/', '_'))
        local.write_bytes(data)
        print('%s=%s' % (path, local))


if __name__ == '__main__':
    main()
