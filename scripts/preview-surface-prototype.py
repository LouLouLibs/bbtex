#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Display-only BBEdit prototype. No TeX compilation or document saves."""
import argparse
import base64
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("image", type=Path, help="A previously rendered PNG")
args = parser.parse_args()
image = base64.b64encode(args.image.read_bytes()).decode("ascii")
page = ROOT / "dist/preview-surface/bbtex-snippet-prototype.html"
page.parent.mkdir(parents=True, exist_ok=True)
page.write_text('''<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>LaTeX Snippet — Display Prototype</title>
<style>
body{margin:0;padding:16px;background:#f5f5f7;color:#25252a;font:13px -apple-system,sans-serif}
header{display:flex;justify-content:space-between;align-items:center;margin-bottom:16px}
small{color:#686872}figure{margin:0;background:white;border-radius:8px;padding:12px}
img{width:100%;height:auto;display:block}p{color:#686872;line-height:1.5;margin-bottom:0}
</style></head><body><header><strong>LaTeX Snippet</strong><small>Display prototype</small></header>
<figure><img alt="x squared plus y squared equals z squared" src="data:image/png;base64,''' + image + '''"></figure>
<p>A rendered image inside BBEdit. This prototype tests window placement and reuse;
it does not compile your selection.</p></body></html>''')

def apple(script, *args):
    return subprocess.check_output(["osascript", "-", *map(str, args)], input=script, text=True).strip()

before = apple('''tell application "BBEdit"
    set w to front text window
    set index of w to 1
    set s to selection
    return (ID of w as text) & "|" & (characterOffset of s as text) & "|" & (length of s as text)
end tell''')
source_id, offset, length = before.split("|")
started = time.perf_counter()
subprocess.run(["/usr/local/bin/bbedit", "--background", "--preview", str(page)], check=True)
# --preview returns before WebKit finishes creating/positioning its window.
time.sleep(0.6)
result = apple('''on run argv
    tell application "BBEdit"
        set countFound to 0
        repeat with w in (get web_preview_windows)
            if name of w is "Preview: bbtex-snippet-prototype.html" then
                set countFound to countFound + 1
                set bounds of w to {80, 100, 620, 350}
                set previewID to ID of w
            end if
        end repeat
        set index of window id (item 1 of argv as integer) to 1
        set s to selection
        return (countFound as text) & "|" & (previewID as text) & "|" & (ID of front window as text) & "|" & (characterOffset of s as text) & "|" & (length of s as text)
    end tell
end run''', source_id)
count, preview_id, after_id, after_offset, after_length = result.split("|")
assert count == "1", f"Expected one preview window: {result}"
assert (after_id, after_offset, after_length) == (source_id, offset, length), result
print(f"Preview window {preview_id}; source focus/selection preserved; display calls {time.perf_counter()-started:.3f}s")
print("HTML:", page)
