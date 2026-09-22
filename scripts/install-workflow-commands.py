#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Install on-demand build commands without restarting BBEdit."""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
scripts = Path.home() / "Library/Application Support/BBEdit/Scripts"
commands = {"LaTeX — Show Build Results.sh": "bbtex-bbedit-results.sh",
            "LaTeX — Doctor.sh": "bbtex-bbedit-doctor.sh",
            "LaTeX — Project Outline.sh": "bbtex-bbedit-outline.sh",
            "LaTeX — Insert Citation.sh": "bbtex-bbedit-citation.sh",
            "LaTeX — Insert Reference.sh": "bbtex-bbedit-reference.sh",
            "LaTeX — Open Build Log.sh": "bbtex-bbedit-log.sh",
            "LaTeX — Cancel Build.sh": "bbtex-bbedit-cancel.sh",
            "LaTeX — Clean All Build Output.sh": "bbtex-bbedit-clean-all.sh",
            "LaTeX — Preview Selection.sh": "bbtex-bbedit-preview.sh",
            "LaTeX — Open Preview Log.sh": "bbtex-bbedit-preview-log.sh",
            "LaTeX — Toggle Preview on Save.sh": "bbtex-preview-on-save.sh"}
for name, source in commands.items():
    target = scripts / name
    expected = ROOT / "scripts" / source
    if target.exists() or target.is_symlink():
        if target.is_symlink() and target.resolve() == expected.resolve():
            continue
        raise SystemExit(f"Refusing to overwrite an unrelated file: {target}")
for name, source in commands.items():
    target = scripts / name
    if not target.is_symlink():
        target.symlink_to(ROOT / "scripts" / source)
    assert target.is_file()
    print("Installed:", name)
