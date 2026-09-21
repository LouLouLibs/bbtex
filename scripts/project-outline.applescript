on run argv
    set executablePath to item 1 of argv
    set sourcePath to item 2 of argv
    try
        tell application "BBEdit"
            activate
            set answer to display dialog "Search sections, equations, captions, labels, or filenames. Leave blank for the full outline. Uses saved files; nothing is saved automatically." with title "LaTeX Project Outline" default answer "" buttons {"Cancel", "Search"} default button "Search" cancel button "Cancel"
        end tell
        set queryText to text returned of answer
        set pickerText to do shell script quoted form of executablePath & " outline-picker " & quoted form of sourcePath & " " & quoted form of queryText
        set targetLocation to run script pickerText
        if targetLocation is false then return
        set jumpText to do shell script quoted form of executablePath & " outline-jump " & quoted form of (item 1 of targetLocation) & " " & quoted form of (item 2 of targetLocation) & " " & quoted form of (item 3 of targetLocation)
        run script jumpText
    on error messageText number errorNumber
        if errorNumber is not -128 then tell application "BBEdit" to display alert "Project outline unavailable" message messageText
    end try
end run
