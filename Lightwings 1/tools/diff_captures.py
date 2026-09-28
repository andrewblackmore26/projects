"""Per-screen pixel diff of two capture directories (tools/capture_screens.gd output).

    python tools/diff_captures.py <before_dir> <after_dir> [--tolerance=<screen>:<pixels> ...]

Prints one `measure:` line per screen (changed pixel count, max channel delta, bounding box of the
change) and a summary line. Exit 0 only when every screen present in <before_dir> exists in
<after_dir> with the same size and at most its tolerance of changed pixels (default 0).
"""
import sys
from pathlib import Path

from PIL import Image, ImageChops


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    tolerance = {}
    for option in sys.argv[1:]:
        if option.startswith("--tolerance="):
            name, count = option[len("--tolerance="):].rsplit(":", 1)
            tolerance[name] = int(count)
    if len(args) != 2:
        print(__doc__)
        return 2
    before, after = Path(args[0]), Path(args[1])
    screens = sorted(p.stem for p in before.glob("*.png"))
    failures = 0
    for screen in screens:
        a_path, b_path = before / (screen + ".png"), after / (screen + ".png")
        if not b_path.exists():
            print(f"measure: screen={screen} missing_after=1 ok=0")
            failures += 1
            continue
        a, b = Image.open(a_path).convert("RGB"), Image.open(b_path).convert("RGB")
        if a.size != b.size:
            print(f"measure: screen={screen} size_before={a.size} size_after={b.size} ok=0")
            failures += 1
            continue
        diff = ImageChops.difference(a, b)
        r, g, b_band = diff.split()
        per_pixel = ImageChops.lighter(ImageChops.lighter(r, g), b_band)
        changed = a.size[0] * a.size[1] - per_pixel.histogram()[0]
        max_delta = max(max(band) for band in (diff.getextrema()))
        allowed = tolerance.get(screen, 0)
        ok = changed <= allowed
        if not ok:
            failures += 1
        print(f"measure: screen={screen} changed_px={changed} max_delta={max_delta} bbox={diff.getbbox()} allowed={allowed} ok={int(ok)}")
    print(f"CAPTURE DIFF: {len(screens)} checks, {failures} failures")
    return 1 if failures or not screens else 0


if __name__ == "__main__":
    sys.exit(main())
