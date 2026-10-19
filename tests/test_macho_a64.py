"""aarch64-macos emits a static Mach-O whose ad-hoc code signature hashes every page.

Set NEPER to the compiler image (default build/windows/neper-self.exe). The
executable itself can only be run on a Mac; this checks the bytes Apple's kernel
reads: the load commands, the thread-state pc, and the CodeDirectory.
"""
import hashlib
import os
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
COMPILER = Path(os.environ.get("NEPER", ROOT / "build" / "windows" / "neper-self.exe"))
SOURCE = """use e.mem
use e.os

fn main(a: *mem.Arena, args: []str) -> err {
    let _ = try os.write(os.stdout(), "hello macos\\n")
    ret ok
}
"""


IMPORT_SOURCE = """use e.mem
use e.os

@import("c", "write")
extern fn c_write(fd: i32, buf: usize, n: usize) -> isize

fn main(a: *mem.Arena, args: []str) -> err {
    let text = "hello libSystem\\n"
    let written = c_write(1i32, mem.address_of(&text[0usize]), text.len)
    if written < 0isize { ret os.Failed }
    ret ok
}
"""


def build(directory, text=SOURCE):
    source = Path(directory) / "hello.e"
    source.write_text(text)
    output = Path(directory) / "hello"
    subprocess.run([str(COMPILER), "emit-executable", str(source), str(ROOT), "aarch64", "macos", str(output)], check=True, capture_output=True)
    return output.read_bytes()


def commands(image):
    found = {}
    offset = 32
    for _ in range(struct.unpack_from("<I", image, 16)[0]):
        kind, size = struct.unpack_from("<II", image, offset)
        found[kind] = offset
        offset += size
    return found


class MachOA64(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with tempfile.TemporaryDirectory() as directory:
            cls.image = build(directory)

    def test_header_names_arm64_executable(self):
        magic, cpu, _, kind = struct.unpack_from("<IIII", self.image)
        self.assertEqual((magic, cpu, kind), (0xFEEDFACF, 0x0100000C, 2))

    def test_dyld_loads_it_with_libsystem(self):
        found = commands(self.image)
        for kind in (0xE, 0xC, 0x80000034):  # dylinker, dylib, chained fixups
            self.assertIn(kind, found)
        self.assertNotIn(5, found)  # LC_UNIXTHREAD: the kernel kills arm64 images without dyld
        self.assertEqual(struct.unpack_from("<I", self.image, 24)[0] & 0x200084, 0x200084)

    def test_main_entry_lies_in_the_text_segment(self):
        entry = struct.unpack_from("<Q", self.image, commands(self.image)[0x80000028] + 8)[0]
        self.assertTrue(0x4000 <= entry < len(self.image))
        self.assertEqual(struct.unpack_from("<I", self.image, entry)[0] & 0x9F000000, 0x10000000)  # adr x9, the argument slot literal

    def test_code_directory_hashes_every_page(self):
        found = commands(self.image)
        data_offset, data_size = struct.unpack_from("<II", self.image, found[0x1D] + 8)
        self.assertEqual(data_offset + data_size, len(self.image))
        blob = self.image[data_offset:]
        self.assertEqual(struct.unpack_from(">I", blob)[0], 0xFADE0CC0)
        directory = blob[20:]
        self.assertEqual(struct.unpack_from(">I", directory)[0], 0xFADE0C02)
        hash_offset, _, _, pages, limit = struct.unpack_from(">IIIII", directory, 16)
        self.assertEqual(limit, data_offset)
        for page in range(pages):
            expected = hashlib.sha256(self.image[page * 4096:min((page + 1) * 4096, limit)]).digest()
            self.assertEqual(directory[hash_offset + 32 * page:hash_offset + 32 * page + 32], expected)


class MachOImport(unittest.TestCase):
    def test_libsystem_import_is_a_chained_bind_in_data(self):
        with tempfile.TemporaryDirectory() as directory:
            image = build(directory, IMPORT_SOURCE)
        found = commands(image)
        offset, size = struct.unpack_from("<II", image, found[0x80000034] + 8)
        blob = image[offset:offset + size]
        header = struct.unpack_from("<IIIIIII", blob)
        self.assertEqual(header[4], 1)  # one import
        entry = struct.unpack_from("<I", blob, header[2])[0]
        self.assertEqual(entry & 255, 1)  # libSystem is dylib 1
        self.assertEqual(blob[header[3] + (entry >> 9):].split(bytes([0]))[0], b"_write")
        data = None
        position = 32
        for _ in range(struct.unpack_from("<I", image, 16)[0]):
            kind, length = struct.unpack_from("<II", image, position)
            if kind == 25 and image[position + 8:position + 24].rstrip(bytes([0])) == b"__DATA":
                data = struct.unpack_from("<QQQQ", image, position + 24)
            position += length
        self.assertIsNotNone(data)
        slot = struct.unpack_from("<Q", image, data[2] + 32)[0]
        self.assertEqual(slot, 1 << 63)  # bind, ordinal 0, end of chain


if __name__ == "__main__":
    unittest.main()
