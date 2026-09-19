#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Check executable bits and Finder stationery metadata after ZIP extraction."""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="bbtex-archive-") as directory:
    subprocess.run(["ditto", "-x", "-k", str(ROOT / "dist/bbtex.bbpackage.zip"), directory], check=True)
    package = Path(directory) / "bbtex.bbpackage/Contents"
    assert os.access(package / "Resources/bbtex", os.X_OK)
    for script in (package / "Scripts").glob("*.sh"):
        assert os.access(script, os.X_OK), script
    templates = list((package / "Stationery").glob("*.tex"))
    assert templates
    for template in templates:
        metadata = bytes.fromhex(subprocess.check_output(
            ["xattr", "-px", "com.apple.FinderInfo", str(template)], text=True))
        assert metadata[8] & 0x08, template
    print("Release archive preserves executable bits and stationery flags")
