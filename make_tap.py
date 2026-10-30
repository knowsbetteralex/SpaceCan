"""Wrap a sjasmplus raw binary into a ZX Spectrum 48K CODE .tap file.
Usage: python make_tap.py space_step02.bin space_step02.tap
The program is loaded at 0x9000 (36864).
"""
from pathlib import Path
from sys import argv
from struct import pack

START_ADDRESS = 0x9000
FILE_NAME = b"SPACEDEMO "  # 10 bytes


def tape_block(flag: int, payload: bytes) -> bytes:
    body = bytes((flag,)) + payload
    checksum = 0
    for value in body:
        checksum ^= value
    body += bytes((checksum,))
    return pack("<H", len(body)) + body


def main() -> None:
    if len(argv) != 3:
        raise SystemExit("Usage: python make_tap.py source.bin output.tap")

    data = Path(argv[1]).read_bytes()
    if not data or START_ADDRESS + len(data) > 0x10000:
        raise SystemExit("Invalid size: program must fit from 0x9000 to 0xFFFF")

    # Header: type 3 = CODE, name, data length, load address, unused param.
    header = bytes((3,)) + FILE_NAME + pack("<HHH", len(data), START_ADDRESS, 0x8000)
    tape = tape_block(0x00, header) + tape_block(0xFF, data)
    Path(argv[2]).write_bytes(tape)
    print(f"Created {argv[2]} ({len(data)} program bytes, start {START_ADDRESS})")


if __name__ == "__main__":
    main()
