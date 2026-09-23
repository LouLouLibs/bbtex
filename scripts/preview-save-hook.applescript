on documentDidSave(myDoc)
    try
        tell application "BBEdit"
            set f to get file of myDoc
            set sourcePath to POSIX path of f
            set cursorLine to 0
            set sourceID to 0
            try
                set frontFile to get file of front text document
                if sourcePath is POSIX path of frontFile then
                    set cursorLine to startLine of selection
                    set sourceID to ID of front window
                end if
            end try
        end tell
        -- Same rule as bbtex and the scripts: BBTEX_STATE_DIR, else XDG_STATE_HOME/bbtex.
        set stateDirectory to do shell script "printf '%s/' \"${BBTEX_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/bbtex}\""
        set workerPath to POSIX path of (path to home folder) & "Library/Application Support/BBEdit/Scripts/LaTeX — Toggle Preview on Save.sh"
        set packageWorker to POSIX path of (path to home folder) & "Library/Application Support/BBEdit/Packages/bbtex.bbpackage/Contents/Scripts/LaTeX — Toggle Preview on Save.sh"
        do shell script "test -f " & quoted form of workerPath & " || test -f " & quoted form of packageWorker
        try
            do shell script "test -f " & quoted form of workerPath
        on error
            set workerPath to packageWorker
        end try
        -- The worker decides whether a full build is pausing previews.
        set commandText to "if [ -f " & quoted form of (stateDirectory & "preview-on-save-source") & " ]; then /bin/bash " & quoted form of workerPath & " --saved " & quoted form of sourcePath & " " & cursorLine & " " & sourceID & " >" & quoted form of (stateDirectory & "preview-on-save.log") & " 2>&1 & fi"
        do shell script commandText
    on error messageText
        do shell script "/usr/bin/logger -t bbtex " & quoted form of messageText
    end try
end documentDidSave
