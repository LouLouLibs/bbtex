on run
    try
        set savedDelimiters to AppleScript's text item delimiters
        set AppleScript's text item delimiters to "/Contents/"
        set pathParts to text items of POSIX path of (path to me)
        set AppleScript's text item delimiters to savedDelimiters
        if (count pathParts) < 2 then error "Keep this script inside its BBEdit package."
        set resourcesPath to item 1 of pathParts & "/Contents/Resources/"
        set env_lib to load script POSIX file (resourcesPath & "environments-lib.scpt")
        set env_lib's binaryPath to resourcesPath & "bbtex"
        tell env_lib to capture_document()
        tell application "BBEdit"
            set answer to display dialog "Wrap selected complete lines, or insert on an empty line. Environment name:" default answer "" with title "Wrap in Environment" buttons {"Cancel", "Wrap"} default button "Wrap" cancel button "Cancel"
        end tell
        tell env_lib to wrap_environment(text returned of answer)
    on error messageText number errorNumber
        if errorNumber is not -128 then tell application "BBEdit" to display alert "Could not wrap environment" message messageText
    end try
end run
