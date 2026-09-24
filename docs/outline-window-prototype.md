# Persistent outline: navigation prototype

This records the implementation and capability checks for issue #1.
The persistent window is available as **LaTeX — Project Outline Window**, or
`bbtex outline-window FILE`. One window stays pinned to each canonical project;
other projects open separate windows. The launcher returns immediately once its
preview exists and reuses the same session when invoked again.
The existing **LaTeX — Project Outline** menu remains unchanged. The prototype
uses the saved project index and opens a BBEdit HTML preview containing indented
entry buttons in an expandable hierarchy. Disclosure triangles collapse/expand
sections; heading buttons navigate. Search matches literal title, kind, context
and file text, ignoring case and common combining accents. Matching descendants
keep their ancestors visible. Clearing search (or Escape) restores expansion;
Return in search opens the first match. Tab and Return use standard HTML buttons. Navigation runs
`Outline.jump`, including disk fingerprints, dirty buffers and source-line checks.
The navigation result is displayed inside the window.

**Refresh saved outline** rereads the pinned project's saved sources without
saving buffers or opening source windows. It preserves search, expansion, selected
entry and scroll position. Entry identity uses file, kind, title, context and an
occurrence number; moving an entry's lines preserves identity, while renaming or
reordering identical duplicates may reset its state. Search temporarily expands
matching branches and retains the underlying expansion state across refresh.
Every refreshed snapshot has a revision: a request from an older snapshot is
rejected rather than interpreted as a different entry. Refresh does not overwrite
the preview HTML file, avoiding a BBEdit reload that would discard UI state.

The page also polls saved sources every two seconds using the same update path.
Unchanged indexes return no content; changed snapshots are applied without source
navigation or window activation. Requests never overlap navigation/refresh. Each
poll includes the displayed revision, so a missed response is retried. This first
implementation checks metadata first, rebuilding on changes, every 30 seconds,
or while index warnings exist (including missing-input recovery). A 121-file,
9,600-entry benchmark took 39 ms to index and 33 ms to render; idle metadata
checks averaged 0.116 ms on the development Mac. Browser rendering latency for
that many entries has not been benchmarked.

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
uses an OCaml loopback-only listener on an ephemeral port. JavaScript POSTs a snapshot
entry number with a random 192-bit session token; requests cannot provide file
paths, shell commands or AppleScript. The listener checks Host and Origin, rejects
GET navigation and out-of-range entries, and bounds header reads and native jumps.
Generated labels/context are HTML-escaped. This local endpoint is private to the
prototype, not a public server or general-purpose command interface.

The first form/iframe implementation failed the user's interaction check: BBEdit
sent navigation to an external browser, which received “Unknown request”. Buttons
now have no navigation target and use `fetch` instead; response text goes into an
inline live status region. The next test exposed a second failure: BBEdit sends
`Origin: x-bbedit-preview://`, so allowing only `null` rejected its fetch requests.
The listener now accepts that exact origin as well as `null`, and returns the
validated origin in its CORS response. The token, Host and POST checks remain
enforced. A POST/readback handshake verifies the actual preview can read the
response before displaying “Connected”. Actual click/Return acceptance remains
confirmed for mouse navigation by the user after the origin fix. The subsequent
tree/search UI was also accepted by the user. Refresh/state retention needs its
own interaction check.

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
real native jumps, verifies the BBEdit POST/readback handshake, checks dirty/stale rejection, and checks closing the window
stops the worker and removes its page. Browser click/Return behavior needs a real
interaction check; HTTP-driven navigation alone does not establish keyboard UX.
Native tests are intentionally not part of unattended CI.

The user accepted automatic updates. Remaining polish includes browser rendering
measurements for very large outlines and persistence across closing/reopening.
The window is now included in menu installation and release packaging.
No unsaved indexing, source saving, or RaTeX changes were
introduced. This prototype stays pinned to its initial project.
