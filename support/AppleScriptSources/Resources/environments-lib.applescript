-- Snapshot-based environment editing. The OCaml helper owns matching and offsets.
property originalText : ""
property originalOffset : 1
property originalLength : 0
property originalID : 0
property binaryPath : ""

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

on helperCommand(commandName, originalValue, extraArguments)
    set temporaryDirectory to do shell script "/usr/bin/mktemp -d -t bbtex-environment"
    try
        my writeUTF8(originalValue, temporaryDirectory & "/snapshot")
        set outputText to do shell script quoted form of binaryPath & " " & commandName & " " & quoted form of (temporaryDirectory & "/snapshot") & " " & extraArguments
        do shell script "/bin/rm -rf " & quoted form of temporaryDirectory
        return outputText
    on error messageText number errorNumber
        do shell script "/bin/rm -rf " & quoted form of temporaryDirectory
        error messageText number 5033
    end try
end helperCommand

on capture_document()
    if binaryPath is "" then error "The environment helper requires its package's Resources/bbtex executable." number 5033
    tell application "BBEdit"
        set doc to front text document
        set originalID to ID of doc
        set originalText to text of doc as text
        set originalOffset to characterOffset of selection of window of doc
        set originalLength to length of selection of window of doc
    end tell
    return doc
end capture_document

on balance_environment given ending:endBool
    set doc to my capture_document()
    if originalLength is not 0 then error "Place the cursor inside the environment without selecting text." number 5033
    set endingText to "false"
    if endBool then set endingText to "true"
    set resultText to my helperCommand("environment-find", originalText, (originalOffset as text) & " " & endingText)
    set locations to run script resultText
    return locations & {doc}
end balance_environment

on change_environment(begin_loc, end_loc, doc, cursor_loc, new_env, old_env)
    considering case
        if new_env is old_env then return
    end considering
    set resultText to my helperCommand("environment-change", originalText, (originalOffset as text) & " " & quoted form of new_env)
    set patch to run script resultText
    my apply_patch(patch)
end change_environment

on plan_wrap(new_env)
    set resultText to my helperCommand("environment-wrap", originalText, (originalOffset as text) & " " & (originalLength as text) & " " & quoted form of new_env)
    return run script resultText
end plan_wrap

on wrap_environment(new_env)
    my apply_patch(my plan_wrap(new_env))
end wrap_environment

on validate_snapshot()
    tell application "BBEdit"
        if ID of front text document is not originalID then error "The active document changed. Run the command again." number 5033
        set doc to text document id originalID
        set currentText to text of doc as text
    end tell
    set temporaryDirectory to do shell script "/usr/bin/mktemp -d -t bbtex-environment"
    try
        my writeUTF8(originalText, temporaryDirectory & "/snapshot")
        my writeUTF8(currentText, temporaryDirectory & "/current")
        do shell script quoted form of binaryPath & " picker-unchanged " & quoted form of (temporaryDirectory & "/snapshot") & " " & quoted form of (temporaryDirectory & "/current")
        do shell script "/bin/rm -rf " & quoted form of temporaryDirectory
    on error messageText number errorNumber
        do shell script "/bin/rm -rf " & quoted form of temporaryDirectory
        error "The document changed. Run the environment command again." number 5033
    end try
    tell application "BBEdit"
        considering case
            if (text of doc as text) is not currentText then error "The document changed. Run the command again." number 5033
        end considering
        if ID of front text document is not originalID then error "The active document changed. Run the command again." number 5033
        if characterOffset of selection of window of doc is not originalOffset or length of selection of window of doc is not originalLength then error "The selection moved. Run the command again." number 5033
    end tell
    return doc
end validate_snapshot

on apply_patch(patch)
    set doc to my validate_snapshot()
    tell application "BBEdit"
        if item 2 of patch is 0 then
            select insertion point before character (item 1 of patch) of doc
        else
            select characters (item 1 of patch) thru ((item 1 of patch) + (item 2 of patch) - 1) of doc
        end if
        set contents of selection of window of doc to item 3 of patch
        set selectedCount to 0
        if (count patch) > 4 then set selectedCount to item 5 of patch
        if selectedCount is 0 then
            select insertion point before character (item 4 of patch) of doc
        else
            select characters (item 4 of patch) thru ((item 4 of patch) + selectedCount - 1) of doc
        end if
    end tell
end apply_patch
