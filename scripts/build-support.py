#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Build reusable BBEdit editing assets. No changes to the installed application."""
import argparse
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent

def build(destination):
    source = ROOT / "support"
    contents = destination / "Contents"
    shutil.copytree(source / "Contents", contents, dirs_exist_ok=True)
    binary = ROOT / "_build/default/bin/main.exe"
    assert binary.is_file(), "Run dune build before building editing support"
    # Dune artifacts can be read-only. Replace an existing copy rather than
    # opening it for writing, so repeat builds work on clean CI runners too.
    resources = contents / "Resources"
    resources.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".bbtex-", dir=resources) as staging:
        staged_binary = Path(staging) / "bbtex"
        shutil.copy2(binary, staged_binary)
        staged_binary.replace(resources / "bbtex")
    shutil.copy2(source / "THIRD-PARTY-NOTICES.md", destination)
    shutil.copy2(source / "README.md", destination)
    for script in sorted((source / "AppleScriptSources").rglob("*.applescript")):
        output = contents / script.relative_to(source / "AppleScriptSources").with_suffix(".scpt")
        output.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["osacompile", "-o", str(output), str(script)], check=True)
    # Git does not retain Finder metadata. Restore the stationery flag on build.
    for template in (contents / "Stationery").glob("*.tex"):
        metadata = subprocess.run(["xattr", "-px", "com.apple.FinderInfo", str(template)],
                                  capture_output=True, text=True)
        info = bytearray.fromhex(metadata.stdout) if metadata.returncode == 0 else bytearray(32)
        info[8] |= 0x08
        subprocess.run(["xattr", "-wx", "com.apple.FinderInfo", info.hex(), str(template)],
                       check=True)
    # Clipping scripts are looked up relative to their clipping set.
    for clipping in (contents / "Clippings").rglob("*"):
        if not clipping.is_file() or clipping.suffix == ".scpt":
            continue
        text = clipping.read_text(errors="replace")
        for name in re.findall(r"#script ([^#]+)#", text):
            assert (clipping.parent / name).is_file(), (clipping, name)
    print(f"Built editing support: {destination}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", nargs="?", type=Path,
                        default=ROOT / "dist/bbtex-support.bbpackage")
    build(parser.parse_args().destination)
