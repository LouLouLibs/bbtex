(** The "LaTeX — Preview Selection" Quick Action: an Automator service,
    restricted to BBEdit, that runs the installed Preview Selection command.
    [build] writes the bundle; [install] copies it into ~/Library/Services. *)

let name = "LaTeX — Preview Selection.workflow"
let identifier = "org.bbtex.preview-selection"
let shell_action = "/System/Library/Automator/Run Shell Script.action"

(* A property-list value, written as XML. [Raw] embeds an XML value copied from
   another plist unchanged. *)
type plist =
  | String of string
  | Bool of bool
  | Integer of int
  | Array of plist list
  | Dict of (string * plist) list
  | Raw of string

let escape text =
  let b = Buffer.create (String.length text) in
  String.iter (function
    | '&' -> Buffer.add_string b "&amp;"
    | '<' -> Buffer.add_string b "&lt;"
    | '>' -> Buffer.add_string b "&gt;"
    | c -> Buffer.add_char b c) text;
  Buffer.contents b

let to_xml value =
  let b = Buffer.create 4096 in
  let rec write indent = function
    | String s -> Printf.bprintf b "%s<string>%s</string>\n" indent (escape s)
    | Bool v -> Printf.bprintf b "%s<%b/>\n" indent v
    | Integer n -> Printf.bprintf b "%s<integer>%d</integer>\n" indent n
    | Raw xml -> Printf.bprintf b "%s%s\n" indent (String.trim xml)
    | Array items ->
      Printf.bprintf b "%s<array>\n" indent;
      List.iter (write (indent ^ "\t")) items;
      Printf.bprintf b "%s</array>\n" indent
    | Dict entries ->
      Printf.bprintf b "%s<dict>\n" indent;
      List.iter (fun (key, v) ->
        Printf.bprintf b "%s\t<key>%s</key>\n" indent (escape key);
        write (indent ^ "\t") v) entries;
      Printf.bprintf b "%s</dict>\n" indent in
  Buffer.add_string b {|<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
|};
  write "" value;
  Buffer.add_string b "</plist>\n";
  Buffer.contents b

(* Runs a command and returns its standard output; fails unless it exits 0. *)
let capture program args =
  let ic = Unix.open_process_args_in program (Array.of_list (program :: args)) in
  let output = In_channel.input_all ic in
  match Unix.close_process_in ic with
  | Unix.WEXITED 0 -> output
  | _ -> raise (Project.Error (Printf.sprintf "%s %s failed" program (String.concat " " args)))

(* One value of a plist file: [Raw] XML for [~xml:true], otherwise its text. *)
let extract ?(xml = false) file key =
  let output = capture "/usr/bin/plutil"
      ["-extract"; key; (if xml then "xml1" else "raw"); "-o"; "-"; file] in
  if not xml then String.trim output
  else
    let start = Project_index.find output 0 "<plist version=\"1.0\">" in
    let stop = Project_index.find output start "</plist>" in
    if stop >= String.length output then raise (Project.Error ("Unexpected plist for " ^ key));
    let start = start + String.length "<plist version=\"1.0\">" in
    String.sub output start (stop - start)

let uuid () =
  let hex n = String.init n (fun _ -> "0123456789ABCDEF".[Random.int 16]) in
  String.concat "-" [hex 8; hex 4; "4" ^ hex 3; String.make 1 "89AB".[Random.int 4] ^ hex 3; hex 12]

(* Uses the installed menu command, so the service follows development symlinks. *)
let command = {|set -eu
export PATH="/Library/TeX/texbin:/opt/homebrew/bin:/usr/local/bin:$PATH"
BB_DOC_PATH=$(/usr/bin/osascript -e 'tell application "BBEdit"' -e 'set f to get file of front text document' -e 'return POSIX path of f' -e 'end tell')
export BB_DOC_PATH
SELECTION_RANGE=$(/usr/bin/osascript -e 'tell application "BBEdit" to get {characterOffset, length} of selection')
worker="$HOME/Library/Application Support/BBEdit/Scripts/LaTeX — Preview Selection.sh"
if [[ ! -f "$worker" ]]; then
    worker="$HOME/Library/Application Support/BBEdit/Packages/bbtex.bbpackage/Contents/Scripts/LaTeX — Preview Selection.sh"
fi
/bin/bash "$worker"
/usr/bin/osascript - "$BB_DOC_PATH" "$SELECTION_RANGE" <<'APPLESCRIPT'
on run argv
    delay 0.3
    set AppleScript's text item delimiters to ","
    set rangeParts to text items of item 2 of argv
    set firstCharacter to item 1 of rangeParts as integer
    set selectionLength to item 2 of rangeParts as integer
    tell application "BBEdit"
        if not frontmost then return
        set d to front text document
        set currentFile to get file of d
        if POSIX path of currentFile is not item 1 of argv then return
        if selectionLength > 0 then select characters firstCharacter thru (firstCharacter + selectionLength - 1) of d
    end tell
end run
APPLESCRIPT
|}

let info () =
  Dict [
    "CFBundleIdentifier", String identifier;
    "NSServices", Array [Dict [
      "NSMenuItem", Dict ["default", String "LaTeX — Preview Selection"];
      "NSMessage", String "runWorkflowAsService";
      "NSRequiredContext", Dict ["NSApplicationIdentifier", String "com.barebones.bbedit"];
      "NSReturnTypes", Array [];
      "NSSendTypes", Array [String "NSStringPboardType"];
      "NSTimeout", String "120000"]]]

let workflow () =
  let action_info = Filename.concat shell_action "Contents/Info.plist" in
  let action = Dict [
    "AMAccepts", Raw (extract ~xml:true action_info "AMAccepts");
    "AMActionVersion", String (extract action_info "CFBundleVersion");
    "AMProvides", Raw (extract ~xml:true action_info "AMProvides");
    "ActionBundlePath", String shell_action;
    "ActionName", String "Run Shell Script";
    "ActionParameters", Dict [
      "COMMAND_STRING", String command;
      "CheckedForUserDefaultShell", Bool true;
      "inputMethod", Integer 0;
      "shell", String "/bin/bash";
      "source", String ""];
    "BundleIdentifier", String "com.apple.RunShellScript";
    "Class Name", String "RunShellScriptAction";
    "InputUUID", String (uuid ());
    "OutputUUID", String (uuid ());
    "UUID", String (uuid ())] in
  Dict [
    "AMDocumentVersion", String "2";
    "actions", Array [Dict ["action", action]];
    "connectors", Dict [];
    "workflowMetaData", Dict [
      "applicationBundleIDsByPath", Dict ["/Applications/BBEdit.app", String "com.barebones.bbedit"];
      "applicationPaths", Array [String "/Applications/BBEdit.app"];
      "inputTypeIdentifier", String "com.apple.Automator.text";
      "outputTypeIdentifier", String "com.apple.Automator.nothing";
      "presentationMode", Integer 11;
      "processesInput", Bool false;
      "serviceInputTypeIdentifier", String "com.apple.Automator.text";
      "serviceOutputTypeIdentifier", String "com.apple.Automator.nothing";
      "serviceProcessesInput", Bool false;
      "useAutomaticInputType", Bool false;
      "workflowTypeIdentifier", String "com.apple.Automator.servicesMenu"]]

let rec mkdir_p path =
  if not (Sys.file_exists path) then begin
    mkdir_p (Filename.dirname path);
    Unix.mkdir path 0o755
  end

(** Writes the bundle into [directory] and returns its path. *)
let build directory =
  Random.self_init ();
  let bundle = Filename.concat directory name in
  let contents = Filename.concat bundle "Contents" in
  mkdir_p contents;
  List.iter (fun (file, value) ->
    Out_channel.with_open_bin (Filename.concat contents file) (fun oc ->
      Out_channel.output_string oc (to_xml value)))
    ["Info.plist", info (); "document.wflow", workflow ()];
  bundle

let run program args = ignore (capture program args)

(** Installs a fresh build into ~/Library/Services, backing up an earlier copy
    of this service into [backups]. Refuses to replace an unrelated service. *)
let install ~backups =
  let home = Sys.getenv "HOME" in
  let target = Filename.concat home ("Library/Services/" ^ name) in
  if Sys.file_exists target then begin
    let existing = extract (Filename.concat target "Contents/Info.plist") "CFBundleIdentifier" in
    if existing <> identifier then
      raise (Project.Error ("Refusing to overwrite an unrelated service: " ^ target));
    mkdir_p backups;
    let stamp = let t = Unix.localtime (Unix.time ()) in
      Printf.sprintf "%04d%02d%02d-%02d%02d%02d-%d" (t.tm_year + 1900) (t.tm_mon + 1) t.tm_mday
        t.tm_hour t.tm_min t.tm_sec (Unix.getpid ()) in
    run "/usr/bin/ditto" [target; Filename.concat backups ("preview-service-backup-" ^ stamp)]
  end;
  let staging = Filename.temp_dir "bbtex-service-" "" in
  Fun.protect ~finally:(fun () -> run "/bin/rm" ["-rf"; staging]) (fun () ->
    let bundle = build staging in
    mkdir_p (Filename.dirname target);
    run "/usr/bin/ditto" [bundle; target]);
  run "/System/Library/CoreServices/pbs" ["-update"];
  target
