"""Build both pre-final SpaceCan TAP variants from a single main.asm.

AY enabled: the four compressed AYM2 tracks and IM2 AY player are included.
Beeper only: AY code and music resources are omitted at assembly time.
Both keep three independent title/victory/game-over beeper melodies.
"""
from pathlib import Path
import re
import subprocess
import sys
import tempfile

from make_tap import build_tap

ROOT = Path(__file__).resolve().parent
AUDIO_FLAG = re.compile(r"(?m)^(AY_MUSIC_ENABLED\s+EQU\s+)[01](?=\s|$)")


def assemble_both(output: Path) -> dict[str, Path]:
    """Build outputs and return their paths; raises on an invalid Z80 build."""
    source = (ROOT / "main.asm").read_text(encoding="utf-8")
    if len(AUDIO_FLAG.findall(source)) != 1:
        raise ValueError("main.asm must define AY_MUSIC_ENABLED exactly once")
    output.mkdir(parents=True, exist_ok=True)
    results = {}
    for ay, name in ((1, "SpaceCan-AY"), (0, "SpaceCan-Beeper")):
        modified = AUDIO_FLAG.sub(lambda match: match.group(1) + str(ay), source)
        temporary = None
        try:
            # Keep source next to main.asm to resolve sjasmplus INCLUDE/INCBIN.
            with tempfile.NamedTemporaryFile(
                mode="w", encoding="utf-8", prefix=".build_variant_",
                suffix=".asm", dir=ROOT, delete=False,
            ) as file:
                file.write(modified)
                temporary = Path(file.name)
            binary = output / (name + ".bin")
            build = subprocess.run(
                ["sjasmplus", "--nologo", "--raw=" + str(binary), str(temporary)],
                cwd=ROOT, capture_output=True, text=True, check=False,
            )
            if build.returncode != 0:
                raise RuntimeError(
                    f"{name} assembly failed: {build.stdout}\n{build.stderr}"
                )
            tape = output / (name + ".tap")
            tape.write_bytes(build_tap(binary.read_bytes()))
            results[name] = tape
            print(f"{name}: {binary.stat().st_size} code bytes, "
                  f"{tape.stat().st_size} TAP bytes")
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)
    if results["SpaceCan-AY"].read_bytes() == results["SpaceCan-Beeper"].read_bytes():
        raise AssertionError("AY-on and AY-off TAPs must be different")
    return results


if __name__ == "__main__":
    target = ROOT / (sys.argv[1] if len(sys.argv) > 1 else "dist")
    if len(sys.argv) > 2:
        raise SystemExit("Usage: python3 build_variants.py [output-dir]")
    assemble_both(target)
