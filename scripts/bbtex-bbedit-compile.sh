#!/bin/bash
# BBEdit compile/results/log entry point. All diagnostics are parsed by bbtex.
set -euo pipefail

REAL_SCRIPT="$(readlink "$0" 2>/dev/null || echo "$0")"
REAL_DIR="$(cd "$(dirname "$REAL_SCRIPT")" && pwd)"
PARENT="$(dirname "$REAL_DIR")"
if [[ -x "$PARENT/Resources/bbtex" ]]; then
    BBTEX="$PARENT/Resources/bbtex"
else
    BBTEX="$PARENT/_build/default/bin/main.exe"
fi

STATE_DIR="${BBTEX_STATE_DIR:-$HOME/.local/state/bbtex}"
mkdir -p "$STATE_DIR"
exec >/dev/null 2>>"$STATE_DIR/last-compile.log"

alert() {
    osascript - "$1" "$2" <<'APPLESCRIPT'
on run argv
    tell application "BBEdit" to display alert (item 1 of argv) message (item 2 of argv) as warning
end run
APPLESCRIPT
}

[[ -n "${BB_DOC_PATH:-}" ]] || { alert "No document open" "Open a saved .tex file first."; exit 1; }
SOURCE="$BB_DOC_PATH"
SOURCE_LINE="${BB_DOC_SELSTART_LINE:-1}"
MODE="${1:-compile}"

parse_output() {
    STATUS="" SUMMARY="" LOG="" PDF="" APPLESCRIPT_FILE="" MESSAGE=""
    while IFS= read -r line; do
        case "${line%%: *}" in
            status)           STATUS="${line#*: }" ;;
            summary)          SUMMARY="${line#*: }" ;;
            log)              LOG="${line#*: }" ;;
            pdf)              PDF="${line#*: }" ;;
            applescript_file) APPLESCRIPT_FILE="${line#*: }" ;;
            message)          MESSAGE="${line#*: }" ;;
        esac
    done <<< "$OUTPUT"
}

show_results() {
    if [[ -n "$APPLESCRIPT_FILE" && -f "$APPLESCRIPT_FILE" ]]; then
        osascript "$APPLESCRIPT_FILE" || {
            rm -f "$APPLESCRIPT_FILE"
            alert "Could not show build results" "Use LaTeX — Open Build Log to inspect compiler output."
            return 1
        }
        rm -f "$APPLESCRIPT_FILE"
    fi
}

# These actions never save or rebuild the document.
case "$MODE" in
    --show-results)
        OUTPUT=$("$BBTEX" results "$SOURCE") && EXIT=0 || EXIT=$?
        parse_output
        if [[ $EXIT -ne 0 ]]; then
            alert "Build results unavailable" "${MESSAGE:-Could not read the LaTeX log.}"
            exit 1
        fi
        show_results
        exit 0
        ;;
    --open-log)
        OUTPUT=$("$BBTEX" paths "$SOURCE") && EXIT=0 || EXIT=$?
        parse_output
        if [[ $EXIT -ne 0 ]]; then
            alert "Build log unavailable" "${MESSAGE:-Could not resolve this document.}"
            exit 1
        fi
        if [[ -f "$STATE_DIR/last-compile-source" && "$(cat "$STATE_DIR/last-compile-source")" == "$SOURCE" ]]; then
            bbedit "$STATE_DIR/last-compile.log"
        elif [[ -f "$LOG" ]]; then
            bbedit "$LOG"
        else
            # This is the most recent compiler output, including missing-tool failures.
            bbedit "$STATE_DIR/last-compile.log"
        fi
        exit 0
        ;;
    compile|--choose-engine) ;;
    *) alert "Unknown action" "$MODE"; exit 1 ;;
esac

COMPILE_ARGS=(compile)
if [[ "$MODE" == "--choose-engine" ]]; then
    ENGINE=$(osascript <<'APPLESCRIPT'
tell application "BBEdit"
    set choice to choose from list {"Document settings", "pdflatex", "xelatex", "lualatex", "tectonic"} with title "Compile With…" with prompt "Choose an engine for this build only. Document settings use %!TEX program, or pdflatex by default." default items {"Document settings"} OK button name "Compile" multiple selections allowed false empty selection allowed false
    if choice is false then return ""
    return item 1 of choice
end tell
APPLESCRIPT
    ) || exit 1
    [[ -n "$ENGINE" ]] || exit 0
    [[ "$ENGINE" == "Document settings" ]] || COMPILE_ARGS=(compile --engine "$ENGINE")
fi

if ! osascript -e 'tell application "BBEdit" to save front document'; then
    alert "Could not save document" "Compilation stopped. Save the document and try again."
    exit 1
fi

printf '%s\n' "$SOURCE" > "$STATE_DIR/last-compile-source"
OUTPUT=$("$BBTEX" "${COMPILE_ARGS[@]}" "$SOURCE" 2>"$STATE_DIR/last-compile.log") && EXIT=0 || EXIT=$?
parse_output
if [[ $EXIT -gt 1 || -z "$STATUS" ]]; then
    alert "Compilation could not finish" "${MESSAGE:-Use LaTeX — Open Build Log for details.}"
    exit 1
fi

# Automatic results contain errors only. Empty results close the previous browser.
show_results || exit 1

if [[ "$STATUS" == "success" && -n "$PDF" && -f "$PDF" ]]; then
    SKIM="${BBTEX_SKIM_DISPLAYLINE:-/Applications/Skim.app/Contents/SharedSupport/displayline}"
    if [[ -x "$SKIM" && ( -f "${PDF%.pdf}.synctex.gz" || -f "${PDF%.pdf}.synctex" ) ]]; then
        "$SKIM" -r -g "$SOURCE_LINE" "$PDF" "$SOURCE" || open -g -a Skim "$PDF"
    else
        open -g -a Skim "$PDF"
    fi
fi

# Plain arguments prevent document names/messages from becoming AppleScript code.
osascript - "$STATUS" "$SUMMARY" <<'APPLESCRIPT'
on run argv
    if item 1 of argv is "success" then
        display notification (item 2 of argv) with title "LaTeX: Compiled"
    else
        display notification (item 2 of argv) with title "LaTeX: Build failed"
    end if
end run
APPLESCRIPT
