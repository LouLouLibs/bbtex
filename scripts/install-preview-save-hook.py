#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Install BBEdit's optional save attachment without replacing other hooks."""
import argparse
from pathlib import Path
import subprocess

here = Path(__file__).resolve().parent
packaged = (here / "preview-save-hook.applescript").exists() and here.name == "Resources"
root = here if packaged else here.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--apply", action="store_true")
args = parser.parse_args()
source = here / "preview-save-hook.applescript"
import tempfile
staging = tempfile.TemporaryDirectory(prefix="bbtex-hook-") if packaged else None
output = (Path(staging.name) if staging else root / "dist") / "Document.documentDidSave.scpt"
output.parent.mkdir(parents=True, exist_ok=True)
subprocess.run(["osacompile", "-o", str(output), str(source)], check=True)
print("Built:", output)
if args.apply:
    folder = Path.home() / "Library/Application Support/BBEdit/Attachment Scripts"
    folder.mkdir(parents=True, exist_ok=True)
    target = folder / output.name
    for existing in folder.iterdir():
        if existing.stem in ("Document", "BBEdit", "Document.documentDidSave"):
            if existing == target:
                text = subprocess.check_output(["osadecompile", str(existing)], text=True)
                if "LaTeX — Toggle Preview on Save.sh" in text:
                    continue
            raise SystemExit(f"Existing attachment needs manual integration: {existing}")
    target.write_bytes(output.read_bytes())
    print("Installed:", target)
