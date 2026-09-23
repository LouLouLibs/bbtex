# Persistent outline: navigation prototype

This is the first capability proof for issue #1, not the finished outline window.
The existing **LaTeX — Project Outline** menu remains unchanged. The prototype
uses the saved project index and opens a BBEdit HTML preview containing indented
entry buttons. Tab and Return use standard HTML form controls. Navigation runs
`Outline.jump`, including disk fingerprints, dirty buffers and source-line checks.
The navigation result is displayed inside the window.

To try it from a development checkout:

```sh
opam exec -- dune build
OUTLINE_SESSION=$(mktemp -d /tmp/bbtex-outline.XXXXXX)
_build/default/bin/main.exe outline-window-prototype /absolute/path/main.tex "$OUTLINE_SESSION"
```

The command stays running while the window is open. Repeating it with the same
source and session directory reuses that window. A different project requires
another directory. Close the preview window or interrupt the owning command to
stop the session. The temporary directory retains only its lock file afterward
and can be removed once the process has stopped. An interrupted
session may leave an inert preview window open; close that window manually.

## Presentation and navigation findings

BBEdit's `x-bbedit://open` URLs support source locations, but do not run our
validation before opening them. The installed scripting dictionary exposes HTML
preview windows without a JavaScript-to-AppleScript callback. This proof instead
uses an OCaml loopback-only listener on an ephemeral port. Forms POST a snapshot
entry number with a random 192-bit session token; requests cannot provide file
paths, shell commands or AppleScript. The listener checks Host and Origin, rejects
GET navigation and out-of-range entries, and bounds header reads and native jumps.
Generated labels/context are HTML-escaped. This local endpoint is private to the
prototype, not a public server or general-purpose command interface.

The page's heartbeat proves the HTML-to-loopback connection. It is not sufficient
for lifecycle management: BBEdit can retain a closed page's executing JavaScript.
The prototype also checks BBEdit's preview-window list every two seconds, through
bounded AppleScript calls. Missing windows stop their worker. This polling tradeoff
needs review before making the window a normal installed command.

## Verification and remaining scope

`test/test_outline_window.ml` covers escaping, token/entry/method authorization,
and cross-origin/Host rejection. The explicit native integration test is:

```sh
uv run test/integration/check_outline_window.py
```

It uses disposable sources, verifies window reuse, drives the local endpoint into
real native jumps, checks dirty/stale rejection, and checks closing the window
stops the worker and removes its page. Browser click/Return behavior needs a real
interaction check; HTTP-driven navigation alone does not establish keyboard UX.
Native tests are intentionally not part of unattended CI.

Still pending: expandable tree, stable node IDs, filtering, selection/expansion
retention, explicit/save-driven refresh, project-following policy, and normal menu/
package installation. No unsaved indexing, source saving, or RaTeX changes were
introduced. This prototype is pinned to its initial saved snapshot.
