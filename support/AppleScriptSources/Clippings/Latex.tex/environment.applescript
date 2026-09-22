-- Environment clipping adapted from Nathan Grigg; BBEdit expands the body marker.
on run
    try
        set savedDelimiters to AppleScript's text item delimiters
        set AppleScript's text item delimiters to "/Contents/"
        set pathParts to text items of POSIX path of (path to me)
        set AppleScript's text item delimiters to savedDelimiters
        if (count pathParts) < 2 then error "Keep this clipping script inside its BBEdit package."
        set resourcesPath to item 1 of pathParts & "/Contents/Resources/"
        set env_lib to load script POSIX file (resourcesPath & "environments-lib.scpt")
        set env_lib's binaryPath to resourcesPath & "bbtex"
        tell env_lib to capture_document()
        set dialogResult to display dialog "Which environment?" default answer "" with title "New LaTeX environment" buttons {"Cancel", "Insert"} default button "Insert" cancel button "Cancel"
        set environmentName to text returned of dialogResult
        -- Use the same context/boundary validation as the explicit wrap command.
        tell env_lib to plan_wrap(environmentName)
        tell env_lib to validate_snapshot()
        return "\\begin{" & environmentName & "}" & return & tab & "#SELECTIONORINSERTION#" & return & "\\end{" & environmentName & "}" & return
    on error messageText number errorNumber
        if errorNumber is not -128 then display alert "Could not insert environment" message messageText
        -- An empty result replaces selected text. Abort clipping expansion instead.
        error number -128
    end try
end run
