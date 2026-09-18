-- Adapted from Nathan Grigg's TeX Documentation Lookup; see THIRD-PARTY-NOTICES.md.
-- No dependency on the retired typesetting library.
property package_name : ""

try
    tell application "BBEdit"
        set answer to display dialog "Which LaTeX package?" default answer package_name with title "Package Documentation" buttons {"Cancel", "Open"} default button "Open" cancel button "Cancel"
    end tell
    set package_name to text returned of answer
    if package_name is "" then return
    set command_text to "export PATH=/Library/TeX/texbin:/opt/homebrew/bin:/usr/local/bin:$PATH; command -v texdoc >/dev/null || { echo 'texdoc was not found. Install a TeX distribution to use package documentation.' >&2; exit 127; }; texdoc -- " & quoted form of package_name
    do shell script command_text
on error message_text number error_number
    if error_number is not -128 then
        tell application "BBEdit" to display alert "Could not open documentation" message message_text as warning
    end if
end try
