"""Regression tests for the self-starting ZX Spectrum TAP wrapper."""
from pathlib import Path
from struct import unpack
import tempfile
import unittest
from unittest.mock import patch

import make_tap


def blocks(tap: bytes):
    """Decode and validate every TAP block."""
    pos = 0
    result = []
    while pos < len(tap):
        (length,) = unpack("<H", tap[pos:pos + 2])
        pos += 2
        block = tap[pos:pos + length]
        assert len(block) == length and length >= 2
        assert not __import__("functools").reduce(lambda a, b: a ^ b, block, 0)
        result.append(block)
        pos += length
    assert pos == len(tap)
    return result


class TapeTests(unittest.TestCase):
    def test_autostart_loader_and_code(self):
        program = b"\xF3\x00\x76"  # DI; NOP; HALT as harmless sample
        result = blocks(make_tap.build_tap(program))
        self.assertEqual([x[0] for x in result], [0, 255, 0, 255])
        basic_header, loader, code_header, code = [x[1:-1] for x in result]
        self.assertEqual(basic_header[0], 0)
        self.assertEqual(basic_header[1:11], b"SPACECAN  ")
        self.assertEqual(unpack("<H", basic_header[13:15])[0], 10)
        self.assertEqual(unpack("<H", basic_header[11:13])[0], len(loader))
        self.assertEqual(unpack(">H", loader[:2])[0], 10)
        self.assertEqual(unpack("<H", loader[2:4])[0], len(loader) - 4)
        for token in (0xFD, 0xB0, 0xEF, 0xAF, 0xF9, 0xC0):
            self.assertIn(token, loader)
        self.assertEqual(loader[-1], 13)
        self.assertEqual(code_header[0], 3)
        self.assertEqual(code_header[1:11], b"SPACECAN  ")
        self.assertEqual(unpack("<H", code_header[13:15])[0], 0x9000)
        self.assertEqual(unpack("<H", code_header[11:13])[0], len(program))
        self.assertEqual(code, program)

    def test_rejects_oversize_and_empty_images(self):
        with self.assertRaises(ValueError):
            make_tap.build_tap(b"")
        with self.assertRaises(ValueError):
            make_tap.build_tap(b"x" * (0xFBFD - 0x9000))

    def test_command_line(self):
        with tempfile.TemporaryDirectory() as d:
            source, output = Path(d) / "game.bin", Path(d) / "game.tap"
            source.write_bytes(b"\x00\xC9")
            with patch("sys.argv", ["make_tap.py", str(source), str(output)]):
                make_tap.main()
            self.assertEqual(len(blocks(output.read_bytes())), 4)


if __name__ == "__main__":
    unittest.main()
