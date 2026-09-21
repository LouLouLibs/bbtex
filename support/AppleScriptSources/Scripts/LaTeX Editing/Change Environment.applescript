-- by Nathan Grigg

on main()
	set env_lib_file to path_to_contents() & "Resources/environments-lib.scpt"
	set env_lib to load script POSIX file env_lib_file
	set env_lib's binaryPath to path_to_contents() & "Resources/bbtex"
	tell env_lib to set {env_name, begin_loc, end_loc, cursor_loc, doc} to balance_environment with ending

	try
		display dialog "Change " & env_name & " environment to:" default answer env_name with title "Change environment"
	on error number -128
		error number -128
	end try

	set new_env to text returned of result

	tell env_lib to change_environment(begin_loc, end_loc, doc, cursor_loc, new_env, env_name)
end main

-- Catch and display custom errors; exit silently on cancelled dialogs
try
	main()
on error eStr number eNum partial result rList from badObj to exptectedType
	if eNum = 5033 then
		display dialog eStr buttons {"OK"} with title "Error" default button 1
	else if eNum = 5088 then
		beep
	else if eNum is not -128 then
		error eStr number eNum partial result rList from badObj to exptectedType
	end if
end try

on path_to_contents()
	--- Returns path to "Contents" folder containing the current script
	local delims, split_string
	set delims to AppleScript's text item delimiters
	set AppleScript's text item delimiters to "/Contents/"
	set split_string to text items of POSIX path of (path to me)
	set AppleScript's text item delimiters to delims
	if length of split_string = 1 then error "This script must remain inside the bbtex BBEdit package because it depends on other scripts in that package." number 5033
	return (item 1 of split_string) & "/Contents/"
end path_to_contents
