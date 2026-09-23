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
    set binaryPath to item 1 of argv
    set modeName to item 2 of argv
    set temporaryDirectory to ""
    try
        tell application "BBEdit"
            activate
            set d to front text document
            set documentID to ID of d
            set f to file of d
            set sourcePath to POSIX path of f
            set originalText to text of d as text
            set editorWindow to window of d
            set originalOffset to characterOffset of selection of editorWindow
            set originalLength to length of selection of editorWindow
            set selectedText to contents of selection of editorWindow as text
            set prefixText to ""
            if originalOffset > 1 then set prefixText to contents of characters 1 thru (originalOffset - 1) of d as text
            if modeName is "cite" then
                set promptText to "Search by author, title, year, or citation key. Choose one or more results. Existing citation commands, options, and keys are preserved."
                set titleText to "Insert Citation"
            else
                set promptText to "Search saved labels by name, section, caption, equation text, or filename."
                set titleText to "Insert Reference"
            end if
            set answer to display dialog promptText with title titleText default answer "" buttons {"Cancel", "Search"} default button "Search" cancel button "Cancel"
        end tell
        set temporaryDirectory to do shell script "/usr/bin/mktemp -d -t bbtex-picker"
        my writeUTF8(originalText, temporaryDirectory & "/snapshot")
        my writeUTF8(prefixText, temporaryDirectory & "/prefix")
        my writeUTF8(selectedText, temporaryDirectory & "/selected")
        set queryText to text returned of answer
        if modeName is "cite" then
            set pickerText to do shell script quoted form of binaryPath & " citation-picker " & quoted form of sourcePath & " " & quoted form of queryText
        else
            set pickerText to do shell script quoted form of binaryPath & " reference-picker " & quoted form of sourcePath & " " & quoted form of queryText
        end if
        set choice to run script pickerText
        if choice is not false then
            run script (item 2 of choice)
            set planText to do shell script quoted form of binaryPath & " picker-insert " & quoted form of modeName & " " & quoted form of (temporaryDirectory & "/snapshot") & " " & quoted form of (temporaryDirectory & "/prefix") & " " & quoted form of (temporaryDirectory & "/selected") & " " & quoted form of (item 1 of choice)
            set patch to run script planText
            tell application "BBEdit"
                if ID of front text document is not documentID then error "The active document changed. Run the picker again."
                set d to text document id documentID
                my writeUTF8(text of d as text, temporaryDirectory & "/current")
                do shell script quoted form of binaryPath & " picker-unchanged " & quoted form of (temporaryDirectory & "/snapshot") & " " & quoted form of (temporaryDirectory & "/current")
                considering case
                    if text of d as text is not originalText then error "The document changed while the picker was open. Run the picker again."
                    set currentFile to file of d
                    if POSIX path of currentFile is not sourcePath then error "The document path changed. Run the picker again."
                end considering
                if characterOffset of selection of window of d is not originalOffset or length of selection of window of d is not originalLength then error "The selection moved. Run the picker again."
                set firstCharacter to item 1 of patch
                set characterCount to item 2 of patch
                if characterCount is 0 then
                    select insertion point before character firstCharacter of d
                else
                    select characters firstCharacter thru (firstCharacter + characterCount - 1) of d
                end if
                set contents of selection of window of d to item 3 of patch
            end tell
        end if
    on error messageText number errorNumber
        if temporaryDirectory is not "" then
            do shell script "/bin/rm -rf " & quoted form of temporaryDirectory
            set temporaryDirectory to ""
        end if
        if errorNumber is not -128 then tell application "BBEdit" to display alert "Could not insert selection" message messageText
    end try
    if temporaryDirectory is not "" then do shell script "/bin/rm -rf " & quoted form of temporaryDirectory
end run
