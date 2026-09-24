-- Write the text before and inside a selection, only if it has not moved.
on writeUTF8(valueText, filePath)
    set handle to open for access (POSIX file filePath) with write permission
    try
        set eof handle to 0
        write valueText to handle as «class utf8»
        close access handle
    on error messageText number errorNumber
        close access handle
        error messageText number errorNumber
    end try
end writeUTF8

on run argv
    set windowID to (item 1 of argv) as integer
    set expectedOffset to (item 2 of argv) as integer
    set expectedLength to (item 3 of argv) as integer
    set workDirectory to item 4 of argv
    tell application "BBEdit"
        set w to text window id windowID
        set d to document of w
        if characterOffset of selection of w is not expectedOffset or length of selection of w is not expectedLength then error "The selection moved."
        set selectedText to contents of selection of w as text
        set prefixText to ""
        if expectedOffset > 1 then set prefixText to contents of characters 1 thru (expectedOffset - 1) of d as text
    end tell
    my writeUTF8(prefixText, workDirectory & "/prefix")
    my writeUTF8(selectedText, workDirectory & "/selected")
end run
