"""Create a self-starting ZX Spectrum 48K TAP from sjasmplus raw binary.

Usage: python3 make_tap.py SpaceCan.bin SpaceCan.tap

The TAP contains two files: a BASIC loader (auto-run line 10) followed
by CODE loaded at #9000. The loader executes CLEAR 36863, LOAD "" CODE,
then RANDOMIZE USR 36864. No extra libraries are needed.
"""
from pathlib import Path
from struct import pack
from sys import argv

START_ADDRESS = 0x9000
CODE_END_LIMIT = 0xFBFD  # Exclusive: keep IM2's 512-byte stack reserve
FILE_NAME = b"SPACECAN  "  # Exactly 10 ZX Spectrum header bytes
AUTOSTART_LINE = 10

# Tokenised Spectrum BASIC: CLEAR VAL "36863": LOAD "" CODE:
# RANDOMIZE USR VAL "36864". VAL avoids hidden five-byte numeric literals.
BASIC_LINE = (
    b'\xFD \xB0"36863": \xEF "" \xAF: \xF9 \xC0 \xB0"36864"\x0D'
)


def tape_block(flag: int, payload: bytes) -> bytes:
    """Encode one TAP block with its little-endian length and XOR checksum."""
    body = bytes((flag,)) + payload
    checksum = 0
    for value in body:
        checksum ^= value
    body += bytes((checksum,))
    return pack("<H", len(body)) + body


def build_tap(data: bytes) -> bytes:
    """Return a complete, autostarting TAP without writing files."""
    if not data or START_ADDRESS + len(data) >= CODE_END_LIMIT:
        raise ValueError(
            "Program must fit into #9000..#FBFC (before reserved IM2 stack)"
        )

    line = pack(">H", AUTOSTART_LINE) + pack("<H", len(BASIC_LINE)) + BASIC_LINE
    # BASIC header type 0, autostart line 10, variables start after program.
    basic_header = bytes((0,)) + FILE_NAME + pack(
        "<HHH", len(line), AUTOSTART_LINE, len(line)
    )
    # CODE header type 3, load at #9000.
    code_header = bytes((3,)) + FILE_NAME + pack(
        "<HHH", len(data), START_ADDRESS, 0x8000
    )
    return (
        tape_block(0, basic_header)
        + tape_block(0xFF, line)
        + tape_block(0, code_header)
        + tape_block(0xFF, data)
    )


def main() -> None:
    if len(argv) != 3:
        raise SystemExit("Usage: python3 make_tap.py source.bin output.tap")
    data = Path(argv[1]).read_bytes()
    try:
        tap = build_tap(data)
    except ValueError as exc:
        raise SystemExit(str(exc)) from exc
    Path(argv[2]).write_bytes(tap)
    print(f"Created {argv[2]} ({len(data)} program bytes, autorun at #9000)")


if __name__ == "__main__":
    main()
