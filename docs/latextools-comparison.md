# bbtex vs Sublime LaTeXTools — Feature Comparison

This document compares bbtex (our BBEdit LaTeX tool) against Sublime Text's
LaTeXTools plugin, which is the gold standard for editor-integrated LaTeX
workflows. The comparison helps prioritize what to build next and what to
deliberately leave out.

## Feature Matrix

### Build System

| Feature | LaTeXTools | bbtex | Notes |
|---------|-----------|-------|-------|
| latexmk integration | Yes (default builder) | Yes | Both use `-cd`, `-synctex=1`, `-interaction=nonstopmode` |
| pdflatex | Yes | Yes | |
| xelatex | Yes | Yes | |
| lualatex | Yes | Yes | |
| tectonic | No | Yes | bbtex advantage — tectonic is a separate code path |
| bibtex auto-detection | Yes (via latexmk) | Yes (via latexmk) | latexmk handles this transparently |
| biber auto-detection | Yes (via latexmk) | Yes (via latexmk) | |
| Custom builder plugins | Yes (Python subclass) | No | LaTeXTools has a full builder plugin API |
| Script builder | Yes (run arbitrary commands) | No | Could add a `%!TEX build` directive |
| `--shell-escape` support | Yes (via `%!TEX options`) | No | Missing: `%!TEX options` directive |
| `--output-directory` | Yes (via directive) | No | |
| `--jobname` | Yes (via directive) | No | |
| `-file-line-error` | Not explicit | Yes | bbtex passes this to latexmk |

### Error / Warning Display

| Feature | LaTeXTools | bbtex | Notes |
|---------|-----------|-------|-------|
| Error parsing from .log | Yes (regex-based) | Yes (OCaml parser) | bbtex's parser is more structured |
| Clickable errors → source | Yes (output panel) | Yes (BBEdit results browser) | Different UI, same concept |
| Navigate next/prev error | Yes (ST commands) | Yes (BBEdit results browser) | BBEdit has built-in navigation |
| Errors with file attribution | Yes | Yes | Both track file stacks |
| Multi-line error handling | Partial | Yes | bbtex handles `l.<N>` termination |
| Warning display | Yes | Yes | |
| Bad box display | Optional | Yes | LaTeXTools has a toggle for bad boxes |
| Syntax-highlighted output | Yes (custom syntax) | Partial (ANSI colors in text mode) | |
| Filter by severity | No | Not yet | Could add `--errors-only`, `--no-badbox` |
| 79-char line unwrapping | Unknown | Not yet | Known gap — the #1 cause of parser failures |

### %!TEX Directives

| Directive | LaTeXTools | bbtex | Notes |
|-----------|-----------|-------|-------|
| `%!TEX root` | Yes | Yes | LaTeXTools requires it on line 1; bbtex searches first 50 lines |
| `%!TEX program` | Yes | Yes | |
| `%!TEX TS-program` | Yes (TeXShop compat) | No | Could add as alias for `program` |
| `%!TEX options` | Yes | No | Passes arbitrary flags to compiler |
| `%!TEX output_directory` | Yes | No | |
| `%!TEX aux_directory` | Yes (MiKTeX only) | No | Not relevant on macOS |
| `%!TEX jobname` | Yes | No | |
| `%!TEX spellcheck` | Yes | No | Editor-specific, not relevant for bbtex |
| `%!TEX encoding` | No | Yes (parsed, unused) | bbtex parses it but doesn't act on it |

### SyncTeX

| Feature | LaTeXTools | bbtex | Notes |
|---------|-----------|-------|-------|
| Forward search (source → PDF) | Yes | Yes | |
| Inverse search (PDF → source) | Yes | Yes (via Skim config) | Needs manual Skim preference setup |
| Skim support | Yes (default on macOS) | Yes | |
| Preview.app support | Yes (limited) | No | Preview has no sync API |
| `synctex=1` passed to compiler | Yes | Yes | |
| `displayline` integration | Yes | Yes | Falls back to AppleScript |

### Multi-file Projects

| Feature | LaTeXTools | bbtex | Notes |
|---------|-----------|-------|-------|
| `%!TEX root` directive | Yes | Yes | |
| Project-level root setting | Yes (`.sublime-project`) | No | BBEdit has no equivalent mechanism |
| Jump to `\input{}` file | Yes (`C-l, C-j`) | No | Editor feature, not parser |
| Create referenced file | Yes (`C-l, C-o`) | No | Editor feature |
| Cross-file ref/cite completion | Yes | No | Editor feature |

### Editor Integration (LaTeXTools-specific features)

These are Sublime Text editor features that don't directly translate to a
CLI tool like bbtex, but could partially be implemented via BBEdit scripts
or clippings:

| Feature | LaTeXTools | bbtex | Feasibility for BBEdit |
|---------|-----------|-------|----------------------|
| Citation autocomplete | Yes | No | Hard — needs bib parsing + BBEdit completion API |
| Reference autocomplete | Yes | No | Hard — needs label scanning + completion API |
| Environment autocomplete | Yes | No | Possible via BBEdit clippings |
| Command snippets (CWL) | Yes | No | BBEdit already has LaTeX clippings |
| Smart snippets (context-aware) | Yes | No | Hard — needs math/text mode detection |
| Equation preview (inline) | Yes | No | Not possible in BBEdit |
| Image preview on hover | Yes | No | Not possible in BBEdit |
| Goto sections/labels | Yes (`C-r`) | No | Could build via BBEdit's function popup |
| Text wrapping commands | Yes (`C-l, C-e` etc.) | No | Already in BBEdit's Latex.bbpackage clippings |

### Keyboard Shortcuts

| Action | LaTeXTools | bbtex (proposed) |
|--------|-----------|-----------------|
| Compile | `Cmd+B` | `Shift+Cmd+K` (contextual to .tex) |
| Forward search | `Cmd+L, J` | TBD |
| Jump to included file | `Cmd+L, Cmd+J` | N/A |
| Wrap in `\emph{}` | `Cmd+L, Cmd+E` | Existing clippings |
| Wrap in `\textbf{}` | `Cmd+L, Cmd+B` | Existing clippings |

### Configuration

| Feature | LaTeXTools | bbtex | Notes |
|---------|-----------|-------|-------|
| Global config file | Yes (JSON) | No | Could add `~/.config/bbedit/bbtex.conf` |
| Per-project config | Yes (`.sublime-project`) | Via `%!TEX` directives | Directives cover most cases |
| Builder selection | Yes | Via `%!TEX program` | |
| Viewer selection | Yes (per-platform) | Hardcoded to Skim | Skim is the only macOS viewer with good sync |
| Bibliography parser mode | Yes (traditional/new) | N/A | bbtex doesn't parse .bib files |

## What bbtex does better

1. **Tectonic support** — LaTeXTools has no tectonic builder.
2. **Structured log parser** — OCaml algebraic types vs regex-based parsing.
   The parser is a proper single-pass state machine with a file stack, not
   a bag of regexes.
3. **`%!TEX root` anywhere in first 50 lines** — LaTeXTools requires it on
   line 1.
4. **Standalone CLI tool** — usable from any editor, CI, or Makefile. Not
   tied to one editor's plugin API.
5. **`-file-line-error`** — bbtex passes this flag to latexmk, which
   produces cleaner error messages in the log.

## What LaTeXTools does better

1. **Autocomplete ecosystem** — citations, references, environments,
   glossary entries. This is where LaTeXTools really shines and where bbtex
   will likely never compete (it would require deep editor integration
   that BBEdit's plugin model doesn't easily support).
2. **Equation/image preview** — inline rendering using Sublime's phantom
   API. Not feasible in BBEdit.
3. **Builder plugin system** — extensible Python API for custom builders.
   bbtex's shell scripts are simpler but less extensible.
4. **`%!TEX options`** — passing arbitrary compiler flags. Easy to add.
5. **Per-project settings** — `.sublime-project` file overrides. bbtex
   relies on `%!TEX` directives, which cover most cases but can't
   configure things like viewer or builder settings.

## Roadmap priorities

Based on this comparison, the highest-value additions for bbtex would be:

### Must have (core workflow)
- [ ] 79-character line unwrapping in log parser (most common parser failure)
- [ ] `%!TEX options` directive (for `--shell-escape` etc.)
- [ ] BBEdit keyboard shortcut configuration guide
- [ ] Proper installation script (symlinks into BBEdit Scripts folder)

### Should have (quality of life)
- [ ] `%!TEX TS-program` as alias for `program` (TeXShop compat)
- [ ] `--errors-only` / `--no-badbox` filter flags
- [ ] Clean log (no errors/warnings) should produce no output in bbedit mode
- [ ] Config file (`~/.config/bbedit/bbtex.conf`) for defaults

### Nice to have (if time allows)
- [ ] `%!TEX output_directory` support
- [ ] `%!TEX jobname` support
- [ ] A "clean" subcommand to remove aux/log/synctex files
- [ ] Watch mode (recompile on save) — though BBEdit scripts trigger on demand
- [ ] JSONL output format for CI/tooling integration

### Deliberately out of scope
- Citation/reference autocomplete (needs editor-level integration)
- Inline equation/image preview (not feasible in BBEdit)
- Smart context-aware snippets (BBEdit's clipping system is sufficient)
- Custom builder plugins (shell scripts are sufficient)
