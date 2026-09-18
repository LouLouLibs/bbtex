#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Install built editing support; archive the retired package without deleting it."""
import argparse
import datetime
from pathlib import Path
import plistlib
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parent.parent

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="apply changes (default: preview)")
    parser.add_argument("--restart", action="store_true", help="quit/reopen BBEdit to reload packages")
    args = parser.parse_args()
    source = ROOT / "dist/bbtex-support.bbpackage"
    support = Path.home() / "Library/Application Support/BBEdit"
    destination = support / "Packages/bbtex-support.bbpackage"
    legacy = support / "Packages/Latex.bbpackage"
    texlab = shutil.which("texlab")
    server_link = support / "Language Servers/texlab"
    assert (source / "Contents/Resources/environments-lib.scpt").is_file(), "Build support first"
    assert (source / "Contents/Scripts/LaTeX Editing/Package Documentation.scpt").is_file()
    print(f"Install {source} → {destination}")
    print(f"Archive {legacy} if present; preserve all clippings and stationery")
    print(f"TexLab: {texlab or 'not installed'}")
    if not args.apply:
        print("Preview only. Use --apply --restart to install.")
        return
    if args.restart:
        subprocess.run(["osascript", "-e", 'tell application "BBEdit" to quit'],
                       check=True, timeout=120)
    if subprocess.run(["pgrep", "-x", "BBEdit"], stdout=subprocess.DEVNULL).returncode == 0:
        # Allow a normal quit to finish; never force quit.
        for _ in range(40):
            time.sleep(.25)
            if subprocess.run(["pgrep", "-x", "BBEdit"], stdout=subprocess.DEVNULL).returncode != 0:
                break
        else:
            raise SystemExit("Quit BBEdit before installing; no files changed.")
    backup = support / "Backups" / ("bbtex-" + datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f"))
    backup.mkdir(parents=True)
    staged = backup / "new-support.bbpackage"
    # Python's copytree does not preserve macOS FinderInfo stationery flags.
    subprocess.run(["ditto", str(source), str(staged)], check=True)
    moved = []
    shortcut_file = support / "Setup/Not Menu Shortcuts.plist"
    shortcut_raw = shortcut_file.read_bytes() if shortcut_file.exists() else None
    created_server_link = False
    published = False
    try:
        # Move the complete legacy package, including any user-customized originals.
        for existing in (legacy, destination):
            if existing.exists():
                saved = backup / existing.name
                shutil.move(str(existing), saved)
                moved.append((saved, existing))
        shutil.move(str(staged), destination)
        published = True
        if texlab and not server_link.exists() and not server_link.is_symlink():
            server_link.parent.mkdir(parents=True, exist_ok=True)
            server_link.symlink_to(texlab)
            created_server_link = True
        if shortcut_raw is not None:
            (backup / shortcut_file.name).write_bytes(shortcut_raw)
            shortcuts = plistlib.loads(shortcut_raw)
            renamed = {
                "Tools/05)Change environment.scpt": "Change Environment.scpt",
                "Tools/05)Star-unstar environment.scpt": "Toggle Starred Environment.scpt",
                "Tools/Declare Math Operator.scpt": "Declare Math Operator.scpt",
                "Tools/TeX Documentation Lookup.scpt": "Package Documentation.scpt",
            }
            # Preserve any custom key for an imported editing command.
            for old, new in renamed.items():
                key = "LocalDomain;Scripts;" + old
                if key in shortcuts:
                    shortcuts["LocalDomain;Scripts;LaTeX Editing/" + new] = shortcuts.pop(key)
            fmt = plistlib.FMT_BINARY if shortcut_raw.startswith(b"bplist") else plistlib.FMT_XML
            shortcut_file.write_bytes(plistlib.dumps(shortcuts, fmt=fmt, sort_keys=False))
        assert (destination / "Contents/Resources/environments-lib.scpt").is_file()
        print("Installed. Backup:", backup)
    except BaseException:
        if published and destination.exists():
            shutil.move(str(destination), backup / "failed-install.bbpackage")
        for saved, original in reversed(moved):
            shutil.move(str(saved), original)
        if shortcut_raw is not None:
            shortcut_file.write_bytes(shortcut_raw)
        if created_server_link:
            server_link.unlink()
        raise
    finally:
        if args.restart:
            subprocess.run(["open", "-a", "BBEdit"], check=True)

if __name__ == "__main__":
    main()
