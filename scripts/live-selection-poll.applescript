-- Report the front BBEdit selection on stderr whenever it changes (see live_selection.ml).
on run argv
    set fastInterval to (item 1 of argv) as real
    set slowInterval to (item 2 of argv) as real
    set lastReport to ""
    repeat
        if application "BBEdit" is not running then return
        set report to "idle"
        set waitFor to slowInterval
        try
            tell application "BBEdit"
                set previewOpen to false
                repeat with p in (get web_preview_windows)
                    if name of p starts with "Preview: bbtex-snippet-" then set previewOpen to true
                end repeat
                if not previewOpen then
                    set report to "closed"
                else if frontmost then
                    set waitFor to fastInterval
                    set w to front text window
                    set f to file of w
                    if f is not missing value then
                        set s to selection of w
                        set report to (POSIX path of f) & tab & (ID of w as text) & tab & ((characterOffset of s) as text) & tab & ((length of s) as text) & tab & ((startLine of s) as text)
                    end if
                end if
            end tell
        end try
        if report is not lastReport then
            log report
            set lastReport to report
        end if
        delay waitFor
    end repeat
end run
