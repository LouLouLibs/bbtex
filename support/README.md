# Editing support

The clippings, stationery, and environment helpers are adapted from Nathan Grigg's
Latex.bbpackage. See THIRD-PARTY-NOTICES.md for attribution and the BSD license.

Kept: clippings (including scripted insert/close environment), stationery,
environment library, change environment, toggle star, and declare math operator.
Package Documentation now calls texdoc without the old typesetting library.

Retired: old Typeset, Open PDF, Python log parser/directive parser, log browser,
and git-information build command. The full installed original is archived.

Build from this repository:

    dune build
    scripts/build-support.sh

Preview the install:

    scripts/install-support.sh

Install (quits and reopens BBEdit; respects unsaved-document prompts):

    scripts/install-support.sh --apply --restart

Development uses bbtex-support.bbpackage plus the existing script symlinks.
Release packages include the same assets inside bbtex.bbpackage.

The one-time migration from the retired Latex.bbpackage (archiving it and
carrying over its keyboard shortcuts) has been removed. If that package is still
installed, `install-support.sh` stops and points to the old
`scripts/install-support.py` in git history.

Change/Toggle/Close Environment use the bundled OCaml executable to match literal
environment tags in the unsaved buffer. Matching skips comments, common verbatim
regions, and common macro definitions; malformed nesting is rejected. Rename and
toggle use one undoable edit and preserve the cursor. They do not expand TeX
macros or evaluate conditionals. See `docs/bbedit-editing.md` in the repository.

Wrap in Environment preserves complete selected lines and their indentation, or
inserts an empty environment on a blank line. Scripted environment clippings
validate names and abort safely on cancellation/invalid input. The links and
images clipping folder adds native URL, width, and filename placeholders; these
require hyperref or graphicx in the document, respectively.
