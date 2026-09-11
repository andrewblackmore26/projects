#!/usr/bin/env python3
"""Ad-hoc pixel probes over a captured frame.

The engine prints the authoritative `measure:` lines (see GodotProject/scripts/
Capture.cs); this script is for looking at a PNG afterwards without re-running
Godot: a background check, a pixel probe, and a diff between two captures.

    python Tools/measure_frame.py bg   FRAME.png [--expect 5,5,7] [--tol 2]
    python Tools/measure_frame.py at   FRAME.png X,Y [X,Y ...]
    python Tools/measure_frame.py diff A.png B.png [--threshold 40]

Exit code 0 when every named gate passed, 1 otherwise.
"""

import argparse
import collections
import sys

import numpy as np
from PIL import Image


def load(path):
    img = Image.open(path).convert("RGB")
    return np.asarray(img).astype(np.int16)


def background(px, grid=3):
    """Modal pixel over a coarse grid: a sparse frame is mostly background, so the mode IS the background."""
    sample = px[::grid, ::grid].reshape(-1, 3)
    counts = collections.Counter(map(tuple, sample))
    (rgb, n) = counts.most_common(1)[0]
    return np.array(rgb, dtype=np.int16), n / len(sample)


def cmd_bg(args):
    px = load(args.frame)
    bg, share = background(px)
    luma = px @ np.array([0.2126, 0.7152, 0.0722])
    print(f"bg={bg[0]},{bg[1]},{bg[2]} share={share:.3f} meanLuma={luma.mean():.1f} peak={int(px.max())}")
    if args.expect:
        want = np.array([int(v) for v in args.expect.split(",")], dtype=np.int16)
        ok = bool((np.abs(bg - want) <= args.tol).all())
        print(f"  [{'PASS' if ok else 'FAIL'}] background {tuple(int(v) for v in bg)} vs expected {tuple(int(v) for v in want)} +-{args.tol}")
        return 0 if ok else 1
    return 0


def cmd_at(args):
    px = load(args.frame)
    h, w, _ = px.shape
    for spec in args.points:
        x, y = (int(v) for v in spec.split(","))
        if not (0 <= x < w and 0 <= y < h):
            print(f"  ({x},{y}) out of bounds {w}x{h}")
            continue
        r, g, b = (int(v) for v in px[y, x])
        luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
        print(f"  ({x},{y}) rgb={r},{g},{b} luma={luma:.1f}")
    return 0


def cmd_diff(args):
    a, b = load(args.a), load(args.b)
    if a.shape != b.shape:
        print(f"FAIL: shapes differ {a.shape} vs {b.shape}")
        return 1
    d = np.abs(a - b).max(axis=2)
    changed = int((d > args.threshold).sum())
    print(f"changed={changed} of {d.size} pixels (threshold {args.threshold}) maxDelta={int(d.max())}")
    return 0


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("bg")
    s.add_argument("frame")
    s.add_argument("--expect", default=None)
    s.add_argument("--tol", type=int, default=2)
    s.set_defaults(fn=cmd_bg)

    s = sub.add_parser("at")
    s.add_argument("frame")
    s.add_argument("points", nargs="+")
    s.set_defaults(fn=cmd_at)

    s = sub.add_parser("diff")
    s.add_argument("a")
    s.add_argument("b")
    s.add_argument("--threshold", type=int, default=40)
    s.set_defaults(fn=cmd_diff)

    args = p.parse_args()
    sys.exit(args.fn(args))


if __name__ == "__main__":
    main()
