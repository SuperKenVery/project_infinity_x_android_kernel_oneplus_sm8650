#!/usr/bin/env python3
"""Apply the Ace 3 Pro +5 C shell-charge strategy to an existing DTBO image."""

import argparse
import struct
from pathlib import Path

DT_TABLE_MAGIC = 0xD7B7AB1E
FDT_MAGIC = 0xD00DFEED
PROPERTY = 3
END_NODE = 2
NOP = 4
END = 9
ORIGINAL = (1, 0, 380, 19, 1, 0, 370, 400, 14, 2, 0, 390, 420, 9, 3, 1, 410, 430, 7, 4, 2, 420, 440, 5, 4, 3)
UPDATED = (1, 0, 430, 19, 1, 0, 420, 450, 14, 2, 0, 440, 470, 9, 3, 1, 460, 480, 7, 4, 2, 470, 490, 5, 4, 3)


def be32(data, offset):
    return struct.unpack_from(">I", data, offset)[0]


def align4(value):
    return (value + 3) & ~3


def patch_fdt(image, fdt_offset, fdt_size):
    if be32(image, fdt_offset) != FDT_MAGIC:
        raise ValueError("selected DTBO entry is not an FDT")
    struct_off = fdt_offset + be32(image, fdt_offset + 8)
    strings_off = fdt_offset + be32(image, fdt_offset + 12)
    struct_size = be32(image, fdt_offset + 36)
    pos, end, matches = struct_off, struct_off + struct_size, []
    while pos < end:
        token = be32(image, pos)
        pos += 4
        if token == PROPERTY:
            length, nameoff = be32(image, pos), be32(image, pos + 4)
            value_at = pos + 8
            name_at = strings_off + nameoff
            name_end = image.index(0, name_at)
            name = bytes(image[name_at:name_end]).decode("ascii")
            if name == "oplus,general_strategy_data":
                if length != len(ORIGINAL) * 4:
                    raise ValueError("unexpected strategy property length")
                values = struct.unpack_from(">26I", image, value_at)
                if values not in (ORIGINAL, UPDATED):
                    raise ValueError("strategy data does not match the expected corvette profile")
                matches.append(value_at)
            pos = align4(value_at + length)
        elif token == 1:
            pos = align4(image.index(0, pos) + 1)
        elif token in (END_NODE, NOP):
            continue
        elif token == END:
            break
        else:
            raise ValueError(f"unexpected FDT token {token}")
    if len(matches) != 2:
        raise ValueError(f"expected two shell strategy properties, found {len(matches)}")
    for value_at in matches:
        struct.pack_into(">26I", image, value_at, *UPDATED)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("base_dtbo", type=Path)
    parser.add_argument("output_dtbo", type=Path)
    parser.add_argument("--entry", type=int, default=6, help="Android DTBO entry index (default: 6)")
    args = parser.parse_args()
    image = bytearray(args.base_dtbo.read_bytes())
    if be32(image, 0) != DT_TABLE_MAGIC:
        raise ValueError("not an Android DTBO image")
    header_size, entry_size, entry_count = be32(image, 4), be32(image, 12), be32(image, 16)
    if args.entry < 0 or args.entry >= entry_count or entry_size < 8:
        raise ValueError("invalid DTBO entry index")
    entry_at = header_size + args.entry * entry_size
    fdt_size, fdt_offset = be32(image, entry_at), be32(image, entry_at + 4)
    if fdt_offset + fdt_size > len(image):
        raise ValueError("DTBO entry exceeds image size")
    patch_fdt(image, fdt_offset, fdt_size)
    args.output_dtbo.write_bytes(image)


if __name__ == "__main__":
    main()
