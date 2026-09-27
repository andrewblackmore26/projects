"""Encode native-size Godot capture sequences; retain PNGs and their simulation manifest."""
import argparse
import json
from pathlib import Path
from PIL import Image


def encode_sequence(folder: Path, manifest: dict, entries: list, output: Path) -> Path:
    fps = float(manifest["fps"])
    # The final endpoint documents bounds, but is not another playback interval.
    count = min(len(entries), round(float(manifest.get("seconds", len(entries) / fps)) * fps))
    frames = []
    for entry in entries[:count]:
        name = entry["frame"] if isinstance(entry, dict) else entry
        with Image.open(folder / name) as source:
            frames.append(source.convert("RGB").quantize(colors=128, dither=Image.Dither.NONE))
    durations = [round((i + 1) * 100 / fps) * 10 - round(i * 100 / fps) * 10 for i in range(count)]
    frames[0].save(output, save_all=True, append_images=frames[1:], duration=durations,
                   loop=0, optimize=True, disposal=2)
    print(f"{output}: {len(frames)} frames, {sum(durations)}ms, {output.stat().st_size} bytes")
    return output


def encode(folder: Path) -> None:
    manifest = json.loads((folder / "manifest.json").read_text(encoding="utf-8-sig"))
    if "frames" in manifest:
        encode_sequence(folder, manifest, manifest["frames"], folder.with_suffix(".gif"))
        return
    for page in manifest["pages"]:
        if "frames" in page:
            encode_sequence(folder, manifest, page["frames"], folder / (page["id"] + ".gif"))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("folders", nargs="+", type=Path)
    for folder in parser.parse_args().folders:
        encode(folder.resolve())
