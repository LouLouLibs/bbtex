#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Build/install a selected-text Quick Action restricted to BBEdit."""
import argparse
import datetime
from pathlib import Path
import plistlib
import shutil
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[1]
PACKAGED = Path(__file__).resolve().parent.name == "Resources"
NAME = "LaTeX — Preview Selection.workflow"
IDENTIFIER = "org.bbtex.preview-selection"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--apply", action="store_true")
args = parser.parse_args()
import tempfile
staging = tempfile.TemporaryDirectory(prefix="bbtex-service-") if PACKAGED else None
destination = (Path(staging.name) if staging else ROOT / "dist") / NAME
contents = destination / "Contents"
contents.mkdir(parents=True, exist_ok=True)

# Use the installed menu command, so the service follows development symlinks.
command = r'''set -eu
export PATH="/Library/TeX/texbin:/opt/homebrew/bin:/usr/local/bin:$PATH"
BB_DOC_PATH=$(/usr/bin/osascript -e 'tell application "BBEdit"' -e 'set f to get file of front text document' -e 'return POSIX path of f' -e 'end tell')
export BB_DOC_PATH
SELECTION_RANGE=$(/usr/bin/osascript -e 'tell application "BBEdit" to get {characterOffset, length} of selection')
worker="$HOME/Library/Application Support/BBEdit/Scripts/LaTeX — Preview Selection.sh"
if [[ ! -f "$worker" ]]; then
    worker="$HOME/Library/Application Support/BBEdit/Packages/bbtex.bbpackage/Contents/Scripts/LaTeX — Preview Selection.sh"
fi
/bin/bash "$worker"
/usr/bin/osascript - "$BB_DOC_PATH" "$SELECTION_RANGE" <<'APPLESCRIPT'
on run argv
    delay 0.3
    set AppleScript's text item delimiters to ","
    set rangeParts to text items of item 2 of argv
    set firstCharacter to item 1 of rangeParts as integer
    set selectionLength to item 2 of rangeParts as integer
    tell application "BBEdit"
        if not frontmost then return
        set d to front text document
        set currentFile to get file of d
        if POSIX path of currentFile is not item 1 of argv then return
        if selectionLength > 0 then select characters firstCharacter thru (firstCharacter + selectionLength - 1) of d
    end tell
end run
APPLESCRIPT
'''
service = {"NSMenuItem": {"default": "LaTeX — Preview Selection"},
           "NSMessage": "runWorkflowAsService", "NSSendTypes": ["NSStringPboardType"],
           "NSRequiredContext": {"NSApplicationIdentifier": "com.barebones.bbedit"},
           "NSReturnTypes": [], "NSTimeout": "120000"}
info = {"CFBundleIdentifier": IDENTIFIER, "NSServices": [service]}
action_info = plistlib.loads(Path("/System/Library/Automator/Run Shell Script.action/Contents/Info.plist").read_bytes())
action = {"ActionBundlePath": "/System/Library/Automator/Run Shell Script.action",
          "ActionName": "Run Shell Script", "BundleIdentifier": "com.apple.RunShellScript",
          "AMActionVersion": action_info["CFBundleVersion"], "Class Name": "RunShellScriptAction",
          "AMAccepts": action_info["AMAccepts"], "AMProvides": action_info["AMProvides"],
          "ActionParameters": {"COMMAND_STRING": command, "shell": "/bin/bash",
                               "inputMethod": 0, "source": "", "CheckedForUserDefaultShell": True},
          "UUID": str(uuid.uuid4()), "InputUUID": str(uuid.uuid4()), "OutputUUID": str(uuid.uuid4())}
workflow = {"AMDocumentVersion": "2", "actions": [{"action": action}], "connectors": {},
            "workflowMetaData": {"workflowTypeIdentifier": "com.apple.Automator.servicesMenu",
             "applicationBundleIDsByPath": {"/Applications/BBEdit.app": "com.barebones.bbedit"},
             "applicationPaths": ["/Applications/BBEdit.app"], "useAutomaticInputType": False,
             "serviceInputTypeIdentifier": "com.apple.Automator.text",
             "serviceOutputTypeIdentifier": "com.apple.Automator.nothing",
             "inputTypeIdentifier": "com.apple.Automator.text",
             "outputTypeIdentifier": "com.apple.Automator.nothing",
             "processesInput": False, "serviceProcessesInput": False, "presentationMode": 11}}
for name, data in (("Info.plist", info), ("document.wflow", workflow)):
    (contents / name).write_bytes(plistlib.dumps(data))
print("Built:", destination)
if args.apply:
    target = Path.home() / "Library/Services" / NAME
    if target.exists():
        existing = plistlib.loads((target / "Contents/Info.plist").read_bytes())
        if existing.get("CFBundleIdentifier") != IDENTIFIER:
            raise SystemExit("Refusing to overwrite an unrelated service")
        backup_folder = Path.home() / "Library/Application Support/BBEdit/Backups" if PACKAGED else ROOT / "dist"
        backup_folder.mkdir(parents=True, exist_ok=True)
        backup = backup_folder / ("preview-service-backup-" + datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f"))
        shutil.copytree(target, backup)
    shutil.copytree(destination, target, dirs_exist_ok=True)
    subprocess.run(["/System/Library/CoreServices/pbs", "-update"], check=True)
    print("Installed:", target)
