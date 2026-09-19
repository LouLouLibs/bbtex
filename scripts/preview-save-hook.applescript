on documentDidSave(myDoc)
    try
        tell application "BBEdit"
            set f to get file of myDoc
            set sourcePath to POSIX path of f
            set frontFile to get file of front text document
            if sourcePath is not POSIX path of frontFile then return
            set cursorLine to startLine of selection
            set sourceID to ID of front window
        end tell
        set stateDirectory to POSIX path of (path to home folder) & ".local/state/bbtex/"
        set workerPath to POSIX path of (path to home folder) & "Library/Application Support/BBEdit/Scripts/LaTeX — Toggle Preview on Save.sh"
        set packageWorker to POSIX path of (path to home folder) & "Library/Application Support/BBEdit/Packages/bbtex.bbpackage/Contents/Scripts/LaTeX — Toggle Preview on Save.sh"
        do shell script "test -f " & quoted form of workerPath & " || test -f " & quoted form of packageWorker
        try
            do shell script "test -f " & quoted form of workerPath
        on error
            set workerPath to packageWorker
        end try
        set commandText to "if [ -f " & quoted form of (stateDirectory & "preview-on-save-source") & " ] && ! kill -0 $(cat " & quoted form of (stateDirectory & "suppress-save-preview") & " 2>/dev/null) 2>/dev/null; then /bin/bash " & quoted form of workerPath & " --saved " & quoted form of sourcePath & " " & cursorLine & " " & sourceID & " >" & quoted form of (stateDirectory & "preview-on-save.log") & " 2>&1 & fi"
        do shell script commandText
    on error messageText
        do shell script "/usr/bin/logger -t bbtex " & quoted form of messageText
    end try
end documentDidSave
