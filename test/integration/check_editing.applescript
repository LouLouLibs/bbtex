-- Creates only a disposable document and closes it even if the check fails.
on run argv
    set helper to POSIX file (item 1 of argv)
    set original_text to "\\begin{equation}" & return & "x = 1" & return & "\\end{equation}"
    tell application "BBEdit"
        set scratch to make new text document with properties {contents:original_text, source language:"TeX"}
        set original_text to text of scratch as text
        select insertion point before character 20 of scratch
    end tell
    try
        log "Running first toggle"
        run script helper
        log "Reading changed text"
        tell application "BBEdit" to set changed_text to text of scratch as text
        if changed_text does not contain "\\begin{equation*}" then error "Opening environment was not changed"
        if changed_text does not contain "\\end{equation*}" then error "Closing environment was not changed"
        if changed_text does not contain "x = 1" then error "Body was changed"
        log "Running second toggle"
        run script helper
        tell application "BBEdit" to set restored_text to text of scratch as text
        if restored_text is not original_text then error "Second toggle did not restore the original text"
        tell application "BBEdit" to close scratch saving no
        return "Environment toggle round-trip passed in BBEdit"
    on error error_text number error_number
        tell application "BBEdit" to close scratch saving no
        error error_text number error_number
    end try
end run
