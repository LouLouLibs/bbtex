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
        tell application "BBEdit"
            if characterOffset of selection of window of scratch is not 21 then error "Toggle did not retain the cursor position"
            undo
            if (text of scratch as text) is not original_text then error "One Undo did not restore both tags"
            select insertion point before character 20 of scratch
        end tell
        run script helper
        log "Running second toggle"
        run script helper
        tell application "BBEdit" to set restored_text to text of scratch as text
        if restored_text is not original_text then error "Second toggle did not restore the original text"
        set nested_text to "É😀 \\begin{outer}" & return & "% \\begin{fake}" & return & "\\begin{equation}" & return & "x = 1" & return & "\\end{equation}" & return & "\\end{outer}"
        tell application "BBEdit"
            set contents of scratch to nested_text
            set nested_text to text of scratch as text
            -- BBEdit offsets are UTF-16: É + emoji + space occupy four units.
            select insertion point before character 52 of scratch
        end tell
        run script helper
        tell application "BBEdit"
            set changed_text to text of scratch as text
            if changed_text does not contain "\\begin{equation*}" or changed_text does not contain "\\end{equation*}" then error "Nested environment was not changed"
            if changed_text does not contain "\\begin{outer}" or changed_text does not contain "% \\begin{fake}" then error "Unrelated tags changed"
            if characterOffset of selection of window of scratch is not 53 then error "Unicode cursor position was not retained"
            undo
            if (text of scratch as text) is not nested_text then error "Nested toggle was not one undoable edit"
        end tell
        tell application "BBEdit" to close scratch saving no
        my check_guards(item 2 of argv)
        return "Environment editing: nested toggle, Unicode cursor, one Undo, rename and stale guards passed"
    on error error_text number error_number
        try
            tell application "BBEdit" to close scratch saving no
        end try
        error error_text number error_number
    end try
end run

on check_guards(resourcesPath)
    set env_lib to load script POSIX file (resourcesPath & "/environments-lib.scpt")
    set env_lib's binaryPath to resourcesPath & "/bbtex"
    tell application "BBEdit"
        set scratch to make new text document with properties {contents:"\\begin{equation}x\\end{equation}", source language:"TeX"}
        set original_text to text of scratch as text
        select insertion point before character 17 of scratch
    end tell
    try
        tell env_lib to set {env_name, begin_loc, end_loc, cursor_loc, doc} to balance_environment with ending
        tell env_lib to change_environment(begin_loc, end_loc, doc, cursor_loc, "align", env_name)
        tell application "BBEdit"
            if (text of scratch as text) is not "\\begin{align}x\\end{align}" then error "Rename failed"
            if characterOffset of selection of window of scratch is not 14 then error "Rename cursor mapping failed"
            undo
            if (text of scratch as text) is not original_text then error "Rename Undo failed"
            select insertion point before character 17 of scratch
        end tell
        tell env_lib to set {env_name, begin_loc, end_loc, cursor_loc, doc} to balance_environment with ending
        tell application "BBEdit" to select insertion point before character 18 of scratch
        set refused to false
        try
            tell env_lib to change_environment(begin_loc, end_loc, doc, cursor_loc, "align", env_name)
        on error number 5033
            set refused to true
        end try
        if not refused then error "Moved selection was not rejected"
        tell application "BBEdit"
            if (text of scratch as text) is not original_text then error "Rejected edit changed text"
            select insertion point before character 17 of scratch
        end tell
        tell env_lib to set {env_name, begin_loc, end_loc, cursor_loc, doc} to balance_environment with ending
        tell application "BBEdit"
            set contents of scratch to "\\begin{equation}X\\end{equation}"
            select insertion point before character 17 of scratch
        end tell
        set refused to false
        try
            tell env_lib to change_environment(begin_loc, end_loc, doc, cursor_loc, "align", env_name)
        on error number 5033
            set refused to true
        end try
        if not refused then error "Case-only buffer change was not rejected"
        tell application "BBEdit"
            if (text of scratch as text) does not contain "{equation}X" then error "Rejected edit lost unsaved text"
            close scratch saving no
        end tell
    on error messageText number errorNumber
        tell application "BBEdit" to close scratch saving no
        error messageText number errorNumber
    end try
end check_guards
