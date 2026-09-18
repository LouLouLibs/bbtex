#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Close only disposable bbtex integration-test documents left by failed checks."""
from pathlib import Path
import subprocess
import tempfile

base = Path(tempfile.gettempdir()).resolve()
prefixes = [str(base / name) for name in
            ("bbtex-save-", "bbtex-live-", "bbtex-editor-lsp-", "bbtex-results-")]
result = subprocess.check_output(["osascript", "-", *prefixes], text=True, input='''
on run argv
    set closedCount to 0
    tell application "BBEdit"
        repeat with d in (get text documents)
            try
                set documentFile to get file of d
                set documentPath to POSIX path of documentFile
                repeat with prefix in argv
                    if documentPath starts with (contents of prefix) then
                        close d saving no
                        set closedCount to closedCount + 1
                        exit repeat
                    end if
                end repeat
            end try
        end repeat
    end tell
    return closedCount
end run
''')
print("Closed disposable test documents:", result.strip())
