#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Reassign BBEdit Complete to Shift-Command-C, preserving a backup."""
import datetime
import json
from pathlib import Path
import shutil
import subprocess
import time

support = Path.home() / "Library/Application Support/BBEdit"
path = support / "Setup/Menu Shortcuts.json"

def bindings():
    data = json.loads(path.read_text())
    by_command = {b.get("command"): b for b in data["bindings"]}
    assert 201 in by_command and 206 in by_command, "Unrecognized BBEdit command table"
    conflicts = [b for b in data["bindings"] if b.get("key") == 67 and b.get("modifiers") == 768]
    assert all(b.get("command") in (201, 206) for b in conflicts), conflicts
    return data, by_command

bindings()  # Check before asking the application to close.
subprocess.run(["osascript", "-e", 'tell application "BBEdit" to quit'], check=True, timeout=120)
for _ in range(80):
    if subprocess.run(["pgrep", "-x", "BBEdit"], stdout=subprocess.DEVNULL).returncode:
        break
    time.sleep(0.25)
else:
    raise SystemExit("BBEdit is still open; no shortcut files changed.")

try:
    data, by_command = bindings()
    backup = support / "Backups" / ("completion-" + datetime.datetime.now().strftime("%Y%m%d-%H%M%S"))
    backup.mkdir(parents=True)
    for name in ("Menu Shortcuts.json", "Menu Shortcuts.plist", "Not Menu Shortcuts.plist"):
        source = path.parent / name
        if source.exists():
            shutil.copy2(source, backup / name)
    for command in (201, 206):
        for key in ("key", "keycode", "modifiers"):
            by_command[command].pop(key, None)
    by_command[201].update(key=67, modifiers=768)
    staged = path.with_suffix(".json.tmp")
    staged.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")))
    staged.replace(path)
    _, actual = bindings()
    assert actual[201]["key"] == 67 and actual[201]["modifiers"] == 768
    assert "key" not in actual[206]
    print("Complete: Shift-Command-C; Copy & Append: no shortcut")
    print("Backup:", backup)
finally:
    subprocess.run(["open", "-a", "BBEdit"], check=True)
