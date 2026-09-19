on run argv
    set sourcePath to item 1 of argv
    set binaryPath to item 2 of argv
    set sourceDirectory to do shell script ("/usr/bin/dirname " & quoted form of sourcePath)
    tell application "BBEdit"
        set rootChoice to choose from list {"Keep existing main-file settings", "This file is the main document", "Choose a main .tex file…"} with title "Configure Document" with prompt "An included table or chapter must compile its main document. Choose that file even if it lives in another folder." default items {"Keep existing main-file settings"}
        if rootChoice is false then return
        set rootPath to "-"
        if item 1 of rootChoice is "This file is the main document" then set rootPath to sourcePath
        if item 1 of rootChoice is "Choose a main .tex file…" then
            set rootPath to POSIX path of (choose file with prompt "Select the main .tex document (the file with documentclass)." default location (POSIX file sourceDirectory))
        end if
        set engines to {"Inherit — use main-file / project defaults", "pdflatex — standard LaTeX and publisher templates", "xelatex — system fonts, fontspec, Unicode", "lualatex — modern Unicode and Lua-based packages", "tectonic — automatic package downloads; requires Tectonic", "ratex — experimental Rust TeX engine; separate installation"}
        set engineChoice to choose from list engines with title "Choose Document Engine" with prompt "Follow your template's requirements first. For an included file, inherit the main document's engine. Named project profile engines take precedence over these comments." default items {item 1 of engines}
        if engineChoice is false then return
        set engineName to "inherit"
        repeat with n from 2 to 6
            if item 1 of engineChoice is item n of engines then set engineName to item (n - 1) of {"pdflatex", "xelatex", "lualatex", "tectonic", "ratex"}
        end repeat
        display dialog "Update the root/program comments at the top of this document? Other content is preserved. Your current edits will be saved first; the updated settings will remain unsaved for review. Press ⌘K when ready to save and compile." with title "Apply Document Settings" buttons {"Cancel", "Apply Settings"} default button "Apply Settings" cancel button "Cancel"
        set d to open (POSIX file sourcePath)
        save d
    end tell
    set editScript to do shell script (quoted form of binaryPath & " document-settings " & quoted form of sourcePath & " " & quoted form of engineName & " " & quoted form of rootPath) without altering line endings
    run script editScript
end run
