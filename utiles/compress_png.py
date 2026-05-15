#!/usr/bin/env python3
"""Compress PNG assets for the Godot project.

The default path is tuned for pixel-art backgrounds: keep the original
dimensions, reduce to an adaptive palette, and save with PNG optimization.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Compress a PNG image.")
    parser.add_argument("input", type=Path, help="Source PNG path")
    parser.add_argument(
        "output",
        type=Path,
        nargs="?",
        help="Output PNG path. Defaults to overwriting the source.",
    )
    parser.add_argument(
        "--colors",
        type=int,
        default=256,
        help="Palette color count for adaptive quantization, 2-256. Default: 256",
    )
    parser.add_argument(
        "--lossless",
        action="store_true",
        help="Skip palette quantization and only use PNG optimizer.",
    )
    return parser.parse_args()


def compress_png(source: Path, output: Path, colors: int, lossless: bool) -> None:
    colors = max(2, min(256, colors))

    with Image.open(source) as image:
        image.load()
        has_alpha = image.mode in ("RGBA", "LA") and image.getchannel("A").getextrema() != (255, 255)

        if lossless:
            result = image.copy()
        elif has_alpha:
            result = image.convert("RGBA").quantize(colors=colors, method=Image.Quantize.FASTOCTREE)
        else:
            result = image.convert("RGB").quantize(colors=colors, method=Image.Quantize.MEDIANCUT)

        output.parent.mkdir(parents=True, exist_ok=True)
        result.save(output, format="PNG", optimize=True, compress_level=9)


def main() -> None:
    args = _parse_args()
    source = args.input
    output = args.output or source

    before = source.stat().st_size
    compress_png(source, output, args.colors, args.lossless)
    after = output.stat().st_size
    ratio = after / before if before else 0.0
    print(f"{source} -> {output}")
    print(f"{before:,} bytes -> {after:,} bytes ({ratio:.1%})")


if __name__ == "__main__":
    main()
