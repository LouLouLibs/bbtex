-- Show one reusable HTML preview; preserve the source selection and user placement.
on run argv
    set pagePath to item 1 of argv
    set sourceID to item 2 of argv as integer
    set previewName to "Preview: " & item 3 of argv
    set sourcePath to ""
    if count of argv > 3 then set sourcePath to item 4 of argv
    tell application "BBEdit"
        set foundPreview to false
        repeat with w in (get web_preview_windows)
            if name of w is previewName then set foundPreview to true
        end repeat
    end tell
    if not foundPreview then
        -- Rendering can finish after the user has moved to another document/app.
        tell application "BBEdit"
            if not (exists front window) then return
            if ID of front window is not sourceID then return
            if sourcePath is not "" then
                try
                    set currentFile to get file of window id sourceID
                    if POSIX path of currentFile is not sourcePath then return
                on error
                    return
                end try
            end if
        end tell
        set initialBounds to {80, 100, 620, 380}
        tell application "BBEdit"
            repeat with w in (get web_preview_windows)
                if name of w is "Preview: bbtex-snippet-prototype.html" then
                    set initialBounds to bounds of w
                end if
            end repeat
        end tell
        -- The bbedit command-line tool normally lives in /usr/local/bin.
        do shell script "PATH=/usr/local/bin:/opt/homebrew/bin:$PATH bbedit --background --preview " & quoted form of pagePath
        delay 0.6
        tell application "BBEdit"
            repeat with w in (get web_preview_windows)
                if name of w is previewName then set bounds of w to initialBounds
            end repeat
            -- Reorder BBEdit's own windows without activating the application.
            if exists front window then
                if sourcePath is not "" then
                    try
                        set currentFile to get file of window id sourceID
                        if POSIX path of currentFile is not sourcePath then return
                    on error
                        return
                    end try
                end if
                if (ID of front window is sourceID or name of front window is previewName) and (exists window id sourceID) then set index of window id sourceID to 1
            end if
        end tell
    end if
end run
