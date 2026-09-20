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
export BBTEX_STATE_DIR="$STATE_DIR"
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
    STATUS="" SUMMARY="" LOG="" PDF="" APPLESCRIPT_FILE="" MESSAGE="" ROOT="" ENGINE="" DURATION="" BUILD_LOG=""
    while IFS= read -r line; do
        case "${line%%: *}" in
            root)             ROOT="${line#*: }" ;;
            engine)           ENGINE="${line#*: }" ;;
            duration)         DURATION="${line#*: }" ;;
            build_log)        BUILD_LOG="${line#*: }" ;;
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
        if [[ -n "$BUILD_LOG" && -f "$BUILD_LOG" ]]; then
            bbedit "$BUILD_LOG"
        elif [[ -f "$STATE_DIR/last-compile-source" && "$(cat "$STATE_DIR/last-compile-source")" == "$SOURCE" ]]; then
            bbedit "$STATE_DIR/last-compile.log"
        elif [[ -f "$LOG" ]]; then
            bbedit "$LOG"
        else
            # This is the most recent compiler output, including missing-tool failures.
            bbedit "$STATE_DIR/last-compile.log"
        fi
        exit 0
        ;;
    --cancel|--clean|--clean-all)
        COMMAND="${MODE#--}"
        if [[ "$MODE" == "--clean-all" ]]; then
            osascript -e 'tell application "BBEdit" to display dialog "Remove all build output, including the PDF?" buttons {"Cancel", "Remove"} default button "Cancel" cancel button "Cancel" with title "Clean All Build Output"' || exit 0
        fi
        OUTPUT=$("$BBTEX" "$COMMAND" "$SOURCE") && EXIT=0 || EXIT=$?
        parse_output
        if [[ $EXIT -ne 0 ]]; then
            alert "LaTeX action failed" "${MESSAGE:-The action could not finish.}"
            exit 1
        fi
        osascript - "$SUMMARY" <<'APPLESCRIPT'
on run argv
    display notification (item 1 of argv) with title "LaTeX"
end run
APPLESCRIPT
        exit 0
        ;;
    compile|--choose-engine) ;;
    *) alert "Unknown action" "$MODE"; exit 1 ;;
esac

COMPILE_ARGS=(compile)
if [[ "$MODE" == "--choose-engine" ]]; then
    CHOICES=("Document settings" "Configure Document…" "pdflatex" "xelatex" "lualatex" "tectonic" "ratex")
    PROFILE_OUTPUT=$("$BBTEX" profiles "$SOURCE") || {
        PROFILE_OUTPUT=""
    }
    while IFS= read -r line; do
        [[ "$line" != profile:* ]] || CHOICES+=("Profile: ${line#profile: }")
    done <<< "$PROFILE_OUTPUT"
    CHOICE=$(osascript - "${CHOICES[@]}" <<'APPLESCRIPT'
on run argv
    tell application "BBEdit"
        set choice to choose from list argv with title "Compile With…" with prompt "Choose an engine/profile for one build, or Configure Document… to save defaults." default items {"Document settings"} OK button name "Continue" multiple selections allowed false empty selection allowed false
        if choice is false then return ""
        return item 1 of choice
    end tell
end run
APPLESCRIPT
    ) || exit 1
    [[ -n "$CHOICE" ]] || exit 0
    case "$CHOICE" in
        "Configure Document…")
            SETTINGS_SCRIPT="$REAL_DIR/configure-document.applescript"
            [[ -f "$SETTINGS_SCRIPT" ]] || SETTINGS_SCRIPT="$PARENT/Resources/configure-document.applescript"
            osascript "$SETTINGS_SCRIPT" "$SOURCE" "$BBTEX"
            exit $?
            ;;
        "Document settings") ;;
        "Profile: "*) COMPILE_ARGS=(compile --profile "${CHOICE#Profile: }") ;;
        *) COMPILE_ARGS=(compile --engine "$CHOICE") ;;
    esac
fi

# The save attachment must not start a competing preview during this build.
printf '%s' "$$" > "$STATE_DIR/suppress-save-preview"
trap 'if [[ "$(cat "$STATE_DIR/suppress-save-preview" 2>/dev/null)" == "$$" ]]; then rm -f "$STATE_DIR/suppress-save-preview"; fi' EXIT
"$BBTEX" snippet-stop "$SOURCE" "Automatic preview paused for a full build. Save an equation afterward to refresh."
if ! osascript -e 'tell application "BBEdit" to save front document'; then
    alert "Could not save document" "Compilation stopped. Save the document and try again."
    exit 1
fi

# Source is saved first so edited root directives are visible to the resolver.
SAVE_SCRIPT=$("$BBTEX" save-project "$SOURCE") || {
    alert "Could not resolve project" "Check the root directives and .bbtex settings."; exit 1;
}
if ! osascript - <<< "$SAVE_SCRIPT"; then
    alert "Could not save project" "Compilation stopped because a project file could not be saved."
    exit 1
fi
PATH_ARGS=(paths "${COMPILE_ARGS[@]:1}")
OUTPUT=$("$BBTEX" "${PATH_ARGS[@]}" "$SOURCE") && EXIT=0 || EXIT=$?
parse_output
if [[ $EXIT -ne 0 ]]; then
    alert "Could not resolve build" "${MESSAGE:-Check the project settings.}"; exit 1
fi
osascript - "${ROOT##*/} · $ENGINE" <<'APPLESCRIPT'
on run argv
    display notification (item 1 of argv) with title "LaTeX: Building"
end run
APPLESCRIPT

printf '%s\n' "$SOURCE" > "$STATE_DIR/last-compile-source"
LOCK_SCRIPT="$REAL_DIR/with-preview-lock.pl"
[[ -f "$LOCK_SCRIPT" ]] || LOCK_SCRIPT="$PARENT/Resources/with-preview-lock.pl"
# Let an existing save preview finish before taking the project's build lock.
OUTPUT=$(/usr/bin/perl "$LOCK_SCRIPT" "$STATE_DIR/preview-on-save.lock" "$BBTEX" "${COMPILE_ARGS[@]}" "$SOURCE" 2>"$STATE_DIR/last-compile.log") && EXIT=0 || EXIT=$?
parse_output
if [[ "$STATUS" == "cancelled" ]]; then
    osascript -e 'display notification "Build cancelled" with title "LaTeX"'
    exit 0
fi
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
osascript - "$STATUS" "${ROOT##*/} · $ENGINE · ${DURATION}s — $SUMMARY" <<'APPLESCRIPT'
on run argv
    if item 1 of argv is "success" then
        display notification (item 2 of argv) with title "LaTeX: Compiled"
    else
        display notification (item 2 of argv) with title "LaTeX: Build failed"
    end if
end run
APPLESCRIPT
