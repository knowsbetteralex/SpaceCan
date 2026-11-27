"""Release output contract for separate AY and beeper-only TAPs."""
from pathlib import Path
import importlib.util
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ReleaseVariantsTests(unittest.TestCase):
    def test_build_matrix_exposes_two_distinct_named_taps(self):
        script = (ROOT / "build_variants.py").read_text(encoding="utf-8")
        workflow = (ROOT / ".github/workflows/publish-release.yml").read_text()
        main = (ROOT / "main.asm").read_text()
        self.assertIn('((1, "SpaceCan-AY"), (0, "SpaceCan-Beeper"))', script)
        self.assertIn('from make_tap import build_tap', script)
        self.assertIn('python3 build_variants.py dist', workflow)
        self.assertIn('dist/SpaceCan-AY.tap', workflow)
        self.assertIn('dist/SpaceCan-Beeper.tap', workflow)
        self.assertNotIn('dist/SpaceCan.tap', workflow)
        self.assertIn('    IF AY_MUSIC_ENABLED\n        INCLUDE "ay_driver.asm"', main)
        self.assertIn('        INCLUDE "music.asm"\n    ENDIF', main)

    def test_both_ay_scenes_use_aym2_and_beeper_jingles_differ(self):
        music = (ROOT / "music.asm").read_text()
        import re
        names = re.findall(r'INCBIN "assets/music/([^"]+)"', music)
        self.assertEqual(len(names), 4)
        self.assertEqual(len(set(names)), 4)
        for name in names:
            self.assertEqual((ROOT / "assets/music" / name).read_bytes()[:4], b"AYM2")
        melody = (ROOT / "melodies.asm").read_text()
        names = ("TITLE", "VICTORY", "GAME_OVER")
        seq = []
        for n in names:
            start = melody.index("MELODY_" + n + ":")
            end = melody.index("MELODY_END", start)
            seq.append(melody[start:end].splitlines()[1:])
        self.assertEqual(len(set(map(tuple, seq))), 3)


if __name__ == "__main__":
    unittest.main()
