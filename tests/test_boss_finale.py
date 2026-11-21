"""Structural and resource checks for boss duel, effects and sound cues.

They complement sjasmplus assembly, not a ZX Spectrum emulator playtest.
"""
from pathlib import Path
import re
import struct
import unittest

ROOT = Path(__file__).resolve().parents[1]


def src(path):
    return (ROOT / path).read_text(encoding="utf-8")


class BossFinaleTests(unittest.TestCase):
    def test_door_opens_only_with_first_boss_volley(self):
        boss = src("boss.asm")
        bullets = src("bullets.asm")
        self.assertIn("LD (BOSS_FIGHT_READY),A     ; lock player fire", boss)
        self.assertRegex(
            boss, r"JP BOSS_FIRE_DISPATCH"
        )
        self.assertRegex(
            bullets,
            r"CP STATE_BOSS\s+JR NZ,\.CHECK_POOL\s+"
            r"LD A,\(BOSS_FIGHT_READY\)\s+OR A\s+RET Z",
        )
        self.assertIn("CALL NZ,BOSS_TAKE_HIT", boss)
        self.assertIn("LD (BOSS_FIGHT_READY),A", src("hostile_bullets.asm"))

    def test_clash_effect_has_own_pool_and_dirty_erase(self):
        impacts = src("impacts.asm")
        hostile = src("hostile_bullets.asm")
        renderer = src("renderer.asm")
        self.assertIn("MAX_IMPACTS EQU 4", impacts)
        self.assertIn("IMPACT_FRAME_TICKS EQU 3", impacts)
        self.assertIn("IMPACT_FRAME_COUNT EQU 3", impacts)
        self.assertIn("CALL SPAWN_BULLET_IMPACT", hostile)
        self.assertIn("CALL RENDER_ERASE_BULLET_IMPACTS", renderer)
        self.assertIn("CALL RENDER_DRAW_BULLET_IMPACTS", renderer)
        self.assertIn("CALL RESET_BULLET_IMPACTS", src("menu.asm"))

    def test_boss_death_is_an_80_frame_cinematic(self):
        main = src("main.asm")
        death = src("boss_explosion.asm")
        boss = src("boss.asm")
        self.assertIn("STATE_BOSS_DEATH     EQU 8", main)
        self.assertIn("BOSS_DEATH_TICKS EQU 8", death)
        self.assertIn("BOSS_DEATH_FRAMES EQU 10", death)
        self.assertIn("LD BC,#040B", death)
        self.assertIn("LD DE,#0908", death)
        self.assertIn("JP START_BOSS_DEATH", boss)
        self.assertIn("CALL UPDATE_BOSS_DEATH", main)
        self.assertIn("LD A,STATE_VICTORY", death)
        matrices = re.findall(r"(?m)^BOSS_DEATH_ART_\d+:$", death)
        self.assertEqual(len(matrices), 10)

    def test_both_outputs_get_independent_endings(self):
        menu = src("menu.asm")
        music = src("music.asm")
        melody = src("melodies.asm")
        self.assertIn("MELODY_TITLE", menu)
        self.assertIn("AY_MUSIC_TITLE", menu)
        self.assertIn("MELODY_VICTORY", menu)
        self.assertIn("AY_MUSIC_VICTORY", menu)
        self.assertIn("MELODY_GAME_OVER", menu)
        self.assertIn("AY_MUSIC_GAME_OVER", menu)
        self.assertIn("MELODY_VICTORY:", melody)
        self.assertIn('INCBIN "assets/music/midiver1.aym"', music)
        self.assertIn('INCBIN "assets/music/main_menu1.aym"', music)
        self.assertIn('INCLUDE "aym2_player.asm"', src("main.asm"))
        self.assertIn('INCBIN "assets/music/victory.aym"', music)
        self.assertIn("CALL AY_BOSS_BOOM_TICK", src("im2.asm"))
        self.assertIn("SFX_BOSS    EQU 6", src("sfx.asm"))

    def test_victory_aym1_header_and_commands(self):
        data = (ROOT / "assets/music/victory.aym").read_bytes()
        self.assertEqual(data[:4], b"AYM1")
        self.assertEqual(data[4], 50)
        self.assertEqual(data[5], 0)  # no loop
        self.assertEqual(struct.unpack_from("<H", data, 6)[0], len(data))
        self.assertEqual(struct.unpack_from("<H", data, 8)[0], 0)
        self.assertEqual(struct.unpack_from("<H", data, 10)[0], 0)
        self.assertEqual(struct.unpack_from("<I", data, 12)[0], 2000000)
        pos, frames = 16, 0
        while pos < len(data):
            code = data[pos]
            pos += 1
            if code == 0:
                break
            if code == 0x80:
                mask = struct.unpack_from("<H", data, pos)[0]
                self.assertEqual(mask & ~0x3FFF, 0)
                pos += 2 + mask.bit_count()
                frames += 1
            else:
                self.assertLessEqual(code, 127)
                self.assertGreater(code, 0)
        self.assertEqual(pos, len(data))
        self.assertGreaterEqual(frames, 5)


if __name__ == "__main__":
    unittest.main()
