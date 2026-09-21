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
    uv run scripts/build-support.py

Preview migration:

    uv run scripts/install-support.py

Install (quits and reopens BBEdit; respects unsaved-document prompts):

    uv run scripts/install-support.py --apply --restart

Development uses bbtex-support.bbpackage plus the existing script symlinks.
Release packages include the same assets inside bbtex.bbpackage.
Python helpers use PEP 723 metadata and uv; they require no third-party packages.

If VIRTUAL_ENV points to a removed interpreter, unset it for the invocation and
select an existing interpreter with uv's --python option. Do not repair or install
packages into another environment as part of building bbtex.

Change/Toggle/Close Environment use the bundled OCaml executable to match literal
environment tags in the unsaved buffer. Matching skips comments, common verbatim
regions, and common macro definitions; malformed nesting is rejected. Rename and
toggle use one undoable edit and preserve the cursor. They do not expand TeX
macros or evaluate conditionals. See `docs/bbedit-editing.md` in the repository.
