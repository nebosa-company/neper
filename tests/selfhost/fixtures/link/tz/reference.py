# Builds the neper tz pack from the pinned tzdata release: "NPTZ", a u16 version
# length and the version, a u32 zone count, then per zone a u16 name length, the
# name, a u32 TZif length and the TZif bytes. Prints the pack as a neper string
# literal for lib/e/tz.e when run with "literal", or writes build/tz.pack.
import importlib.resources as resources
import struct
import sys
import tzdata

ZONES = ["UTC", "Europe/London", "Europe/Sofia", "Europe/Berlin", "America/New_York", "America/Los_Angeles",
         "America/Sao_Paulo", "Asia/Tokyo", "Asia/Kolkata", "Asia/Kathmandu", "Australia/Sydney", "Australia/Lord_Howe", "Pacific/Auckland"]


def pack(zones):
    root = resources.files('tzdata.zoneinfo')
    version = tzdata.IANA_VERSION.encode()
    out = b'NPTZ' + struct.pack('<H', len(version)) + version + struct.pack('<I', len(zones))
    for name in zones:
        data = (root / name).read_bytes()
        assert data[:4] == b'TZif'
        out += struct.pack('<H', len(name)) + name.encode() + struct.pack('<I', len(data)) + data
    return out


def literal(data):
    return '"' + "".join("\\x%02x" % b if b < 32 or b > 126 or b in (34, 92) else chr(b) for b in data) + '"'


if __name__ == '__main__':
    data = pack(ZONES)
    if len(sys.argv) > 1 and sys.argv[1] == 'literal':
        print(literal(data))
    else:
        open('build/tz.pack', 'wb').write(data)
        print(len(data), tzdata.IANA_VERSION)
