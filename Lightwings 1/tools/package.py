"""Archive the four verified exports and record SHA-256 hashes. Standard library only."""
from pathlib import Path
import hashlib
import json
import tarfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "builds" / "distributions"
DEST.mkdir(parents=True, exist_ok=True)
manifest = {"game": "Lightship", "version": "0.3.0", "godot": "4.7.2", "godotsteam": "4.22.1", "packages": []}

for flavor in ("campaign", "demo"):
    for platform in ("windows", "linux"):
        folder = ROOT / "builds" / f"{flavor}-{platform}"
        binary = folder / ("Lightship.exe" if platform == "windows" else "Lightship.x86_64")
        if not binary.is_file():
            raise SystemExit(f"Missing export: {binary}")
        (folder / "GODOTSTEAM_LICENSE.txt").write_bytes((ROOT / "addons/godotsteam/license.md").read_bytes())
        (folder / "README.txt").write_text(
            f"LIGHTSHIP — {flavor.upper()}\n\n"
            + ("Launch Lightship.exe. Keep the accompanying DLLs in this folder.\n" if platform == "windows" else "Launch ./Lightship.x86_64. Keep the accompanying shared libraries in this folder.\n")
            + "Offline play needs no Steam account.\n\n"
            + "WASD / left stick: move\nMouse / right stick: aim\nLeft mouse / right trigger: fire\n"
            + "Space / left bumper: secondary 1\nShift / right bumper: secondary 2\nQ / X: secondary 3\n"
            + "Right mouse / left trigger: dash\nE / A: evolve\nTab / Back: map\nEscape / Start: pause\n\n"
            + "Use Options to rebind controls and set audio, auto fire, glow, reduced warp and element labels.\n"
            + "Evolution and map pause combat. Save and Quit preserves the current run.\n\n"
            + ("Demo: campaign levels 1-2 (Lightning and Fire), no tier cap. Ends on the level-2 boss; import your demo save into the full campaign from the main menu.\n" if flavor == "demo" else "Campaign: five elements, 101 preset player hulls across six tiers, five bounded levels on a Chebyshev lattice, one boss per level.\n")
            + "Working art and balance are prepared for review. Steam Deck and partner-account qualification remain pending.\n",
            encoding="utf-8",
        )
        stem = f"lightship-{flavor}-{platform}-x64"
        if platform == "windows":
            archive = DEST / f"{stem}.zip"
            with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as pack:
                for file in sorted(folder.rglob("*")):
                    if file.is_file():
                        pack.write(file, file.relative_to(folder.parent))
        else:
            archive = DEST / f"{stem}.tar.gz"
            def permissions(entry):
                entry.uid = entry.gid = 0
                entry.uname = entry.gname = ""
                entry.mode = 0o755 if entry.isdir() or entry.name.endswith("Lightship.x86_64") else 0o644
                return entry
            with tarfile.open(archive, "w:gz", compresslevel=6) as pack:
                pack.add(folder, arcname=folder.name, filter=permissions)
        with archive.open("rb") as stream:
            sha = hashlib.file_digest(stream, "sha256").hexdigest()
        with binary.open("rb") as stream:
            exe_sha = hashlib.file_digest(stream, "sha256").hexdigest()
        if platform == "windows":
            with zipfile.ZipFile(archive) as pack:
                if pack.testzip() is not None:
                    raise SystemExit(f"Archive CRC check failed: {archive}")
                with pack.open(f"{folder.name}/{binary.name}") as stream:
                    if hashlib.file_digest(stream, "sha256").hexdigest() != exe_sha:
                        raise SystemExit("Archived executable differs")
        else:
            with tarfile.open(archive, "r:gz") as pack:
                entry = pack.getmember(f"{folder.name}/{binary.name}")
                if entry.mode & 0o111 != 0o111:
                    raise SystemExit("Linux executable permission missing")
                with pack.extractfile(entry) as stream:
                    if hashlib.file_digest(stream, "sha256").hexdigest() != exe_sha:
                        raise SystemExit("Archived executable differs")
        manifest["packages"].append({"flavor": flavor, "platform": platform, "file": archive.name, "bytes": archive.stat().st_size, "sha256": sha, "executable_sha256": exe_sha})
        print(f"PACKAGED {archive.name}: {archive.stat().st_size / 1048576:.1f} MiB")
(DEST / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
