"""Build-time checks for independent AY and beeper-engine switches.

No extra TAP releases are produced: alternate modes are assembled only into
temporary binaries to make sure optional audio paths remain valid Z80.
"""
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class AudioSwitchTests(unittest.TestCase):
    def test_both_modes_on_by_default_and_priority_order(self):
        main = (ROOT / "main.asm").read_text(encoding="utf-8")
        sfx = (ROOT / "sfx.asm").read_text(encoding="utf-8")
        self.assertRegex(main, r"(?m)^AY_MUSIC_ENABLED\s+EQU 1$")
        self.assertRegex(main, r"(?m)^BEEPER_ENGINE_ENABLED\s+EQU 1$")
        self.assertIn("JR NZ,.SFX", sfx)
        self.assertIn("JP SFX_ENGINE_TICK", sfx)
        self.assertIn("CP STATE_PLAYING", sfx)
        self.assertIn("CP STATE_BOSS", sfx)
        self.assertIn("RET NZ", sfx)
        self.assertIn("LD A,(SFX_FE_BASE)", sfx)
        self.assertIn("AND #0F", sfx)
        self.assertIn("OR #10", sfx)

    def test_all_audio_combinations_assemble(self):
        assembler = shutil.which("sjasmplus")
        if assembler is None:
            self.skipTest("sjasmplus is not installed")
        main = (ROOT / "main.asm").read_text(encoding="utf-8")
        self.assertEqual(len(re.findall(r"(?m)^AY_MUSIC_ENABLED\s+EQU 1$", main)), 1)
        self.assertEqual(len(re.findall(r"(?m)^BEEPER_ENGINE_ENABLED\s+EQU 1$", main)), 1)
        # The regular 1/1 configuration is assembled by the release job.
        for ay, engine in [(1, 0), (0, 1), (0, 0)]:
            with self.subTest(ay=ay, engine=engine):
                modified = re.sub(
                    r"(?m)^AY_MUSIC_ENABLED\s+EQU 1$",
                    f"AY_MUSIC_ENABLED      EQU {ay}", main,
                )
                modified = re.sub(
                    r"(?m)^BEEPER_ENGINE_ENABLED\s+EQU 1$",
                    f"BEEPER_ENGINE_ENABLED EQU {engine}", modified,
                )
                with tempfile.TemporaryDirectory() as folder:
                    binary = Path(folder) / "variant.bin"
                    # Includes are resolved from the repository root.
                    tmp_source = None
                    try:
                        with tempfile.NamedTemporaryFile(
                            mode="w", encoding="utf-8", suffix=".asm",
                            prefix=".audio_switch_test_", dir=ROOT,
                            delete=False,
                        ) as file:
                            file.write(modified)
                            tmp_source = Path(file.name)
                        proc = subprocess.run(
                            [assembler, "--nologo", f"--raw={binary}", str(tmp_source)],
                            cwd=ROOT, capture_output=True, text=True,
                        )
                        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
                        self.assertTrue(binary.is_file())
                        self.assertGreater(binary.stat().st_size, 1000)
                    finally:
                        if tmp_source is not None:
                            tmp_source.unlink(missing_ok=True)


if __name__ == "__main__":
    unittest.main()
