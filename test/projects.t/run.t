Project resolution, profiles, output paths, engine switching and cleanup, with
fake compilers on PATH. bbtex prints resolved paths; show them relative to here.

  $ export BBTEX_STATE_DIR="$PWD/state" BBTEX_TEST_ROOT="$PWD"
  $ here=$(pwd -P); show() { sed "s|$here|.|g"; }
  $ mkdir bin && export PATH="$PWD/bin:$PATH"

Root chains, self-roots, missing roots and cycles:

  $ printf '%%!TEX root = main.tex\n%%!TEX program = lualatex\n' > main.tex
  $ printf '%%!TEX root = main.tex\n' > middle.tex
  $ printf '%%!TEX root = middle.tex\n' > chapter.tex
  $ bbtex paths chapter.tex | grep -E '^(root|engine):' | show
  root: ./main.tex
  engine: lualatex
  $ printf '%%!TEX root = chapter.tex\n' > middle.tex
  $ bbtex paths chapter.tex | grep -o 'Cyclic %!TEX root directives'
  Cyclic %!TEX root directives
  $ printf '%%!TEX root = absent.tex\n' > middle.tex
  $ bbtex paths chapter.tex | grep -c 'not found'
  1
  $ printf '%%!TEX root = main.tex\n' > middle.tex

Named profiles, an explicit engine over a profile, and a shared output folder:

  $ printf 'root = main.tex\noutput_directory = build output\n\n[profile Draft]\nengine = xelatex\noptions = -halt-on-error\n\n[profile Tectonic]\nengine = tectonic\noptions = --reruns=1\n' > .bbtex
  $ bbtex paths --profile Draft chapter.tex | grep -E '^(engine|pdf):' | show
  pdf: ./build output/main.pdf
  engine: xelatex
  $ bbtex paths --profile Draft --engine pdflatex chapter.tex | grep '^engine:'
  engine: pdflatex
  $ bbtex paths --profile Nope chapter.tex | grep -o 'Unknown build profile: Nope'
  Unknown build profile: Nope

Engine switching with fake latexmk and tectonic that record their arguments:

  $ cat > bin/latexmk <<'FAKE'
  > #!/bin/bash
  > printf '%s\n' "$@" > "$BBTEX_TEST_ROOT/args"
  > out=""; next=0; clean=""
  > for arg in "$@"; do
  >   if [[ $next == 1 ]]; then out="$arg"; next=0; fi
  >   case "$arg" in -outdir=*) out="${arg#-outdir=}";; --outdir) next=1;; -c|-C) clean="$arg";; esac
  >   file="$arg"
  > done
  > base="$out/$(basename "${file%.tex}")"
  > if [[ -n $clean ]]; then rm -f "$base.log" "$base.aux"; [[ $clean != -C ]] || rm -f "$base.pdf"
  > else mkdir -p "$out"; touch "$base.pdf" "$base.log" "$base.aux" "$base.synctex.gz"; fi
  > FAKE
  $ chmod +x bin/latexmk && cp bin/latexmk bin/tectonic
  $ bbtex compile --profile Draft chapter.tex 2>/dev/null | grep '^status:'
  status: success
  $ grep -x -e -pdfxelatex -e -halt-on-error args
  -pdfxelatex
  -halt-on-error
  $ ls "build output"
  main.aux
  main.log
  main.pdf
  main.synctex.gz
  $ bbtex compile --profile Tectonic chapter.tex > /dev/null 2>&1; grep -x -- --outdir args
  --outdir

Clean keeps the PDF; Clean All removes it:

  $ bbtex clean chapter.tex | grep '^summary:'
  summary: Auxiliary files removed; PDF preserved
  $ ls "build output"
  main.pdf
  main.synctex.gz
  $ bbtex clean-all chapter.tex > /dev/null; ls "build output"
  main.synctex.gz
