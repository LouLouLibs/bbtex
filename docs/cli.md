# Command line

The BBEdit commands are thin wrappers around the `bbtex` binary, which also
works from Terminal, a Makefile or CI. A source install links it to
`~/.local/bin/bbtex`. In a release package it is
`bbtex.bbpackage/Contents/Resources/bbtex`.

```sh
bbtex compile paper.tex                    # compile the resolved root
bbtex compile --engine tectonic paper.tex  # one-off engine override
bbtex compile --profile Draft paper.tex    # named profile from .bbtex
bbtex results paper.tex                    # diagnostics from the last log
bbtex cancel paper.tex                     # stop this project's build
bbtex doctor --probe paper.tex             # setup checks with tool versions
```

## Builds

| Command | What it does |
|---|---|
| `compile <file.tex>` | Resolve the root, engine and profile, compile, and report diagnostics. |
| `results <file.tex>` | Show every error, warning and bad box from the project's current log. |
| `paths <file.tex>` | Print the resolved root, engine, log and PDF paths without compiling. |
| `profiles <file.tex>` | List the named profiles in `.bbtex`. |
| `cancel <file.tex>` | Stop the running build for this project and its child processes. |
| `clean <file.tex>` | Remove auxiliary files and keep the PDF. |
| `clean-all <file.tex>` | Remove all build output, including the PDF. |
| `forward-search <file> <line>` | Run a SyncTeX forward search for that source line. |

Options for `compile` (and `paths`):

| Option | Meaning |
|---|---|
| `--engine <name>` | Compile once with `pdflatex`, `xelatex`, `lualatex` or `tectonic`, overriding directives and profiles. |
| `--profile <name>` | Use a named project profile. |
| `--verbose` | Log each step to stderr. |

Engine precedence is: explicit `--engine`, then the selected or default
profile's engine, then the first `%!TEX program` in the source-to-root chain,
then the project `engine`, then `pdflatex`. See
[compiling projects](project-builds.md).

## Logs and directives

| Command | What it does |
|---|---|
| `parse-log <file.log>` | Parse a LaTeX log. `--format text` (default) or `--format bbedit`. |
| `format-results <file.log>` | Parse a log into BBEdit results-browser format. |
| `directives <file.tex>` | Print the `%!TEX` directives found in the first 50 lines. |

## Setup checks

`bbtex doctor [file.tex]` inspects the TeX tools, Skim, TexLab, the installed
package, menu commands and save attachments, without changing anything. Add
`--probe` for bounded version queries, and `--bbedit-support DIRECTORY` to
inspect a non-standard BBEdit support folder. See
[troubleshooting](setup-troubleshooting.md).

## Navigation and previews

| Command | What it does |
|---|---|
| `outline <file.tex> [query]` | Print the saved project outline (sections, equations, captions, labels) as JSON. |
| `outline-window <file.tex>` | Open or reuse the persistent outline window in BBEdit. |
| `preview <file.tex>` | Render selected math, read from stdin, with the root's preamble. |
| `live-selection status\|stop` | Report or stop the live selection preview. |

The remaining commands (`save-project`, `document-settings`, `snippet-*`,
`picker-*`, `environment-*`, `preview-fragment`, `live-selection watch`) are
the protocol between the BBEdit scripts and the binary. They are not a stable
interface.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Success. |
| 1 | The build or preview ran and failed (for example, TeX errors). |
| 2 | A project or setup error, or invalid arguments. |
| 3 | Cancelled. |

Scripts should rely only on zero versus non-zero; codes other than 0 are not a
stable interface.

Run `bbtex --help` for the full list of commands.
