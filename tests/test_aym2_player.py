"""AYM1 + AYM2 regression: exact timed register writes in real SpaceCan music.

Independent reference decoder for validated assets; this is not a CPU emulator.
The sjasmplus workflow separately verifies the new Z80 decoder and memory limit.
"""
from pathlib import Path
import struct
import unittest

ROOT = Path(__file__).resolve().parents[1]
MUSIC = ROOT / "assets" / "music"
SHORT_MASKS = {
    **{0x81 + r: 1 << r for r in range(14)},
    **{0x92 + ch: (3 << (2 * ch)) | (1 << (8 + ch)) for ch in range(3)},
    **{0x95 + ch: 3 << (2 * ch) for ch in range(3)},
    **{0x98 + ch: 0xC0 | (1 << (8 + ch)) for ch in range(3)},
    0x9B: 0x700,
    0x9C: 0x780,
}


def read_frame(data, start, end):
    assert start + 3 <= end and data[start] == 0x80, "truncated frame"
    mask = struct.unpack_from("<H", data, start + 1)[0]
    assert not mask & ~0x3FFF, "bad AY mask"
    stop = start + 3 + mask.bit_count()
    assert stop <= end, "truncated AY values"
    return tuple((r, v) for r, v in zip((r for r in range(14) if mask & (1 << r)),
                                         data[start + 3:stop])), stop


def decode(data):
    dictionary = []
    if data[:4] == b"AYM1":
        _, fps, flags, size, loop, zero, clock = struct.unpack_from("<4sBBHHHI", data)
        assert fps == 50 and not (flags & ~1) and size == len(data) and zero == 0
        start, end = 16, len(data)
    else:
        assert data[:4] == b"AYM2"
        (magic, version, fps, flags, count, size, loop, clock,
         end, bodies, reserved) = struct.unpack_from("<4sBBBBHHIHHI", data)
        assert version == 1 and fps == 50 and not flags & ~1 and count <= 96
        assert size == len(data) and reserved == 0 and clock != 0
        assert 24 < end <= bodies <= size and bodies == end + count * 2
        start, pointer = 24, bodies
        for i in range(count):
            offset = struct.unpack_from("<H", data, end + i * 2)[0]
            assert offset == pointer, "dictionary must be tightly packed"
            frame, pointer = read_frame(data, offset, len(data))
            dictionary.append(frame)
        assert pointer == len(data)
    assert (start <= loop < end-1) if flags & 1 else loop == 0
    boundaries = {}
    pos, frame_count, trace = start, 0, []
    while pos < end:
        at = pos
        boundaries[at] = frame_count  # logical 50Hz loop frame, not file offset
        opcode = data[pos]
        pos += 1
        if opcode == 0:
            assert pos == end and trace, "END must close stream"
            assert not flags & 1 or loop in boundaries
            return tuple(trace), clock, boundaries[loop] if flags & 1 else None
        if opcode == 0x80:
            writes, pos = read_frame(data, at, end)
            trace.append(writes)
            frame_count += 1
        elif 1 <= opcode <= 127:
            trace.extend([()] * opcode)
            frame_count += opcode
        elif data[:4] == b"AYM2" and opcode >= 0xA0:
            assert opcode - 0xA0 < len(dictionary), "bad token"
            trace.append(dictionary[opcode - 0xA0])
            frame_count += 1
        elif data[:4] == b"AYM2" and 0x8F <= opcode <= 0x91:
            trace.append(((8 + opcode - 0x8F, 0),))
            frame_count += 1
        elif data[:4] == b"AYM2" and opcode in SHORT_MASKS:
            mask = SHORT_MASKS[opcode]
            count = mask.bit_count()
            assert pos + count <= end
            trace.append(tuple(zip((r for r in range(14) if mask & (1 << r)),
                                   data[pos:pos + count])))
            pos += count
            frame_count += 1
        else:
            raise AssertionError(f"illegal opcode: {opcode:#x}")
    raise AssertionError("missing END")


class Aym2SpaceCanTests(unittest.TestCase):
    def test_actual_track_headers_and_lossless_register_trace(self):
        for plain, packed, expected_size, count in (
            ("midiver.aym", "midiver1.aym", 2608, 61),
            ("main_menu.aym", "main_menu1.aym", 1867, 26),
        ):
            with self.subTest(packed=packed):
                a = (MUSIC / plain).read_bytes()
                b = (MUSIC / packed).read_bytes()
                self.assertEqual(b[:4], b"AYM2")
                self.assertEqual(len(b), expected_size)
                self.assertEqual(b[7], count)
                self.assertEqual(decode(a), decode(b))
        for original, packed in (("victory.aym", "victory1.aym"),
                                 ("game_over.aym", "game_over1.aym")):
            with self.subTest(packed=packed):
                a, b = (MUSIC / original).read_bytes(), (MUSIC / packed).read_bytes()
                self.assertEqual(decode(a), decode(b))
                self.assertEqual(b[:4], b"AYM2")
                self.assertEqual(b[6], 0)  # ending theme must not loop

    def test_player_dispatch_and_all_aym2_opcodes(self):
        player = (ROOT / "ay_player.asm").read_text()
        decoder = (ROOT / "aym2_player.asm").read_text()
        self.assertIn("JP Z,AYM2_PLAY_HEADER", player)
        self.assertIn("JP Z,AYM2_TICK_DECODE", player)
        self.assertIn("LD (AY_MODE),A", player)
        self.assertIn("AYM2_VALIDATE_DICTIONARY:", decoder)
        self.assertIn("AYM2_STREAM_END_PTR", decoder)
        self.assertIn("AYM2_DICT_BODY_PTR", decoder)
        self.assertIn("LD (AYM2_STREAM_RESUME),HL", decoder)
        self.assertIn("LD HL,(AYM2_STREAM_RESUME)", decoder)
        self.assertIn("CALL AYM2_WRITE_ONE", decoder)
        self.assertIn("JP AYM2_WRITE_ONE", decoder)
        self.assertIn("JP .DECODE", decoder)
        self.assertEqual(decoder.count("    DW #"), 11)
        self.assertIn("AND #3F", decoder)
        self.assertIn("INCLUDE \"aym2_player.asm\"", (ROOT / "main.asm").read_text())
        music = (ROOT / "music.asm").read_text()
        self.assertIn('INCBIN "assets/music/main_menu1.aym"', music)
        self.assertIn('INCBIN "assets/music/midiver1.aym"', music)
        self.assertIn('INCBIN "assets/music/game_over1.aym"', music)
        self.assertIn('INCBIN "assets/music/victory1.aym"', music)

    def test_dictionary_mute_and_short_opcodes_reachable(self):
        frames = [(MUSIC / name).read_bytes() for name in ("midiver1.aym", "main_menu1.aym")]
        self.assertTrue(all(b[7] > 0 for b in frames))
        self.assertTrue(any(b'\x91' in b for b in frames))
        self.assertTrue(any(b'\x80' in b for b in frames))
        self.assertGreater(sum(1 for b in frames for byte in b[24:struct.unpack_from("<H", b, 16)[0]]
                               if byte >= 0xA0), 20)


if __name__ == "__main__":
    unittest.main()
