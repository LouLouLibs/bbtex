-- Uses disposable documents only; exercises the same library as the menu.
on run argv
    set resourcesPath to item 1 of argv
    set clippingsPath to item 2 of argv
    set env_lib to load script POSIX file (resourcesPath & "/environments-lib.scpt")
    set env_lib's binaryPath to resourcesPath & "/bbtex"
    tell application "BBEdit"
        set scratch to make new text document with properties {contents:"  É😀" & linefeed & "    x" & linefeed & "after", source language:"TeX"}
        set original_text to text of scratch as text
        select characters 1 thru 12 of scratch
    end tell
    try
        tell env_lib to capture_document()
        tell env_lib to wrap_environment("quote")
        tell application "BBEdit"
            set expected_text to "  \\begin{quote}" & linefeed & "  É😀" & linefeed & "    x" & linefeed & "  \\end{quote}" & linefeed & "after"
            if (text of scratch as text) is not expected_text then error "Wrapping changed indentation or surrounding text: " & (text of scratch as text)
            if (contents of selection of window of scratch as text) is not ("  É😀" & linefeed & "    x" & linefeed) then error "Wrapped body was not selected"
            undo
            if (text of scratch as text) is not original_text then error "Wrap did not undo in one step"
            set contents of scratch to "  "
            select insertion point before character 3 of scratch
        end tell
        tell env_lib to capture_document()
        tell env_lib to wrap_environment("equation*")
        tell application "BBEdit"
            set expected_text to "  \\begin{equation*}" & linefeed & "  " & tab & linefeed & "  \\end{equation*}"
            -- BBEdit normalizes inserted line endings to its document format.
            if (text of scratch as text) does not contain "\\begin{equation*}" then error "Empty environment was not inserted"
            if characterOffset of selection of window of scratch is not 24 then error "Empty body cursor was misplaced"
            if length of selection of window of scratch is not 0 then error "Empty body was unexpectedly selected"
            undo
            if (text of scratch as text) is not "  " then error "Empty environment Undo failed"
            select insertion point before character 3 of scratch
        end tell
        tell env_lib to capture_document()
        tell application "BBEdit" to set contents of scratch to "  changed"
        set refused to false
        try
            tell env_lib to wrap_environment("quote")
        on error number 5033
            set refused to true
        end try
        if not refused then error "Changed wrap buffer was not rejected"
        tell application "BBEdit"
            if (text of scratch as text) is not "  changed" then error "Rejected wrap lost user edits"
            set contents of scratch to "label"
            select characters 1 thru 5 of scratch
            insert clipping POSIX file (clippingsPath & "/links and images/hyperlink (hyperref)")
            set hyperlink_text to text of scratch as text
            log "Hyperlink clipping: " & hyperlink_text
            if (contents of selection of window of scratch as text) is not "<#url#>" then error "URL placeholder was not selected"
            if hyperlink_text does not contain "\\href{" or hyperlink_text does not contain "{label}" then error "Hyperlink did not preserve selected text"
            if hyperlink_text contains "#PLACEHOLDERSTART#" then error "Placeholder syntax was inserted literally"
            undo
            if (text of scratch as text) is not "label" then error "Hyperlink Undo failed"
            set contents of scratch to ""
            select insertion point before character 1 of scratch
            insert clipping POSIX file (clippingsPath & "/links and images/image (graphicx)")
            set image_text to text of scratch as text
            log "Image clipping: " & image_text
            if (contents of selection of window of scratch as text) is not "<#0.8\\linewidth#>" then error "Width placeholder was not selected"
            if image_text does not contain "\\includegraphics[width=" or image_text does not contain "image.pdf" then error "Image clipping failed"
            if image_text contains "#PLACEHOLDERSTART#" then error "Image placeholder syntax was inserted literally"
            undo
            if (text of scratch as text) is not "" then error "Image Undo failed"
            close scratch saving no
        end tell
        return "Wrapping, empty insertion, body/cursor placement, stale buffer, native clippings and Undo passed"
    on error messageText number errorNumber
        tell application "BBEdit" to close scratch saving no
        error messageText number errorNumber
    end try
end run
