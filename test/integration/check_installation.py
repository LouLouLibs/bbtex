#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Verify a local bbtex editing-support migration without changing settings."""
from pathlib import Path
import plistlib
import subprocess

support = Path.home() / "Library/Application Support/BBEdit"
installed = support / "Packages/bbtex-support.bbpackage"
backups = sorted((support / "Backups").glob("bbtex-*/Latex.bbpackage"))
assert backups, "Legacy package backup missing"
legacy = backups[-1]
assert not (support / "Packages/Latex.bbpackage").exists(), "Legacy package still active"
for category in ("Clippings", "Stationery"):
    count = 0
    for original in (legacy / "Contents" / category).rglob("*"):
        if not original.is_file() or original.suffix == ".scpt" or original.name == ".DS_Store":
            continue
        relative = original.relative_to(legacy)
        assert (installed / relative).read_bytes() == original.read_bytes(), relative
        count += 1
    print(f"Preserved {count} {category.lower()} files")
for template in (installed / "Contents/Stationery").glob("*.tex"):
    info = subprocess.check_output(["xattr", "-px", "com.apple.FinderInfo", str(template)], text=True)
    assert bytearray.fromhex(info)[8] & 8, template
print("Stationery flags verified")
shortcuts = plistlib.loads((support / "Setup/Not Menu Shortcuts.plist").read_bytes())
for script, modifier in [("bbtex-bbedit-compile.sh", 256), ("bbtex-bbedit-compile-with.sh", 768)]:
    matches = [v["KeystrokeRecord"] for k, v in shortcuts.items() if k.endswith("/" + script)]
    assert matches == [{"Modifiers": modifier, "KeyCode": 0, "Key": 75}], (script, matches)
print("⌘K and ⇧⌘K assignments verified")
assert (support / "Language Servers/texlab").is_file()
print("TexLab executable link verified")
process = subprocess.run(["pgrep", "-fl", "texlab"], capture_output=True, text=True)
print("TexLab process:", process.stdout.strip() or "not currently running")
print("Legacy backup:", legacy)
