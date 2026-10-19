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


def build(directory):
    source = Path(directory) / "hello.e"
    source.write_text(SOURCE)
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

    def test_thread_pc_lies_in_the_text_segment(self):
        offset = commands(self.image)[5]
        pc = struct.unpack_from("<Q", self.image, offset + 16 + 32 * 8)[0]
        base = 1 << 32
        self.assertTrue(base < pc < base + len(self.image))
        self.assertEqual(struct.unpack_from("<I", self.image, pc - base)[0], 0x910003F3)  # mov x19, sp

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


if __name__ == "__main__":
    unittest.main()
