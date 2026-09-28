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

Magic comments: Doctor lists every one in the source-to-root chain as used,
mapped or ignored, and a build names the ones that don't fully apply in a
single [bbtex] note.

  $ mkdir magic && cd magic && : > .bbtex
  $ printf '%% !TEX TS-program = xelatex\n%% !TEX encoding = UTF-8 Unicode\n%% !TEX options = -8bit --shell-escape\n%% !BIB TS-program = bibtex8\n%% !TEX output_directory = out\n' > main.tex
  $ printf '%%!TEX root = main.tex\n%%!TEX jobname = draft\n' > chapter.tex
  $ bbtex doctor chapter.tex | grep 'Magic comment'
  [OK] Magic comment: chapter.tex:1 % !TEX root = main.tex (used)
  [WARN] Magic comment: chapter.tex:2 % !TEX jobname = draft (ignored: the PDF is named after the root file; rename the root file instead)
  [OK] Magic comment: main.tex:1 % !TEX TS-program = xelatex (used)
  [INFO] Magic comment: main.tex:2 % !TEX encoding = UTF-8 Unicode (ignored: BBEdit sets the file's encoding and TeX reads the file as saved)
  [WARN] Magic comment: main.tex:3 % !TEX options = -8bit --shell-escape (mapped: options -8bit; can't turn on shell escape: a comment in a downloaded file could run programs. If you trust this document, add options = --shell-escape to .bbtex)
  [OK] Magic comment: main.tex:4 % !BIB TS-program = bibtex8 (mapped: latexmk's BibTeX program, bibtex8)
  [OK] Magic comment: main.tex:5 % !TEX output_directory = out (mapped: output directory out)
  $ bbtex compile chapter.tex 2>/dev/null | grep -E '^(status|pdf|note):' | show
  status: success
  pdf: ./magic/out/main.pdf
  note: [bbtex] Not fully applied: % !TEX jobname, % !TEX options; see LaTeX — Doctor

Document options follow .bbtex's and come before the profile's; shell escape
from a comment is dropped; the BibTeX program reaches latexmk:

  $ cat ../args
  -pdfxelatex
  -interaction=nonstopmode
  -file-line-error
  -synctex=1
  -cd
  -outdir=$TESTCASE_ROOT/magic/out
  -auxdir=$TESTCASE_ROOT/magic/out
  -e
  $bibtex=q/bibtex8 %O %S/
  -8bit
  $TESTCASE_ROOT/magic/main.tex

A shared output folder in .bbtex wins over the comment, and results, clean
and forward search all use it:

  $ printf 'output_directory = build\noptions = -halt-on-error\n[profile Draft]\noptions = -draftmode\n' > .bbtex
  $ bbtex compile --profile Draft chapter.tex 2>/dev/null | grep -E '^(pdf|note):' | show
  pdf: ./magic/build/main.pdf
  note: [bbtex] Not fully applied: % !TEX jobname, % !TEX options, % !TEX output_directory; see LaTeX — Doctor
  $ grep -e '-outdir' -e '-halt' -e '-8bit' -e '-draftmode' ../args | show
  -outdir=./magic/build
  -halt-on-error
  -8bit
  -draftmode
  $ bbtex doctor chapter.tex | grep 'output_directory'
  [WARN] Magic comment: main.tex:5 % !TEX output_directory = out (ignored: output_directory in .bbtex wins (build))
  $ bbtex clean-all chapter.tex > /dev/null; ls build
  main.synctex.gz

Malformed document options stop the build with the comment's location:

  $ printf '%%!TEX options = -outdir=elsewhere\n' > main.tex
  $ bbtex paths chapter.tex | show
  status: error
  message: ./magic/main.tex:1: % !TEX options = -outdir=elsewhere: Option is positional or managed by bbtex: -outdir=elsewhere. Use project settings for engine and output directory; use --option=value for option values.

A document using only root and program gets no warning and no note:

  $ printf '%%!TEX program = pdflatex\n' > main.tex
  $ printf '%%!TEX root = main.tex\n' > chapter.tex
  $ bbtex doctor chapter.tex | grep 'Magic comment'
  [OK] Magic comment: chapter.tex:1 % !TEX root = main.tex (used)
  [OK] Magic comment: main.tex:1 % !TEX program = pdflatex (used)
  $ bbtex compile chapter.tex 2>/dev/null | grep -E '^(status|note):'
  status: success

A file that names no main document builds the one that includes it, as an
Overleaf project does; with several candidates it's built alone, with a pointer
to Configure Document…:

  $ cd .. && mkdir overleaf && cd overleaf && : > .bbtex && mkdir sections
  $ printf '\\documentclass{article}\n\\begin{document}\n\\input{sections/intro}\n\\end{document}\n' > paper.tex
  $ printf '\\section{Intro}\n' > sections/intro.tex
  $ bbtex paths sections/intro.tex | grep -E '^(root|root_source):' | show
  root: ./overleaf/paper.tex
  root_source: found: ../paper.tex includes this file
  $ bbtex compile sections/intro.tex 2>/dev/null | grep -E '^(status|note):'
  status: success
  note: [bbtex] Building ../paper.tex, which includes this file
  $ bbtex paths paper.tex | grep '^root_source:'
  root_source: this file
  $ bbtex doctor sections/intro.tex | grep 'Main file'
  [INFO] Main file: found: ../paper.tex includes this file
  $ cp paper.tex slides.tex
  $ bbtex paths sections/intro.tex | grep -E '^(root|root_source):' | show
  root: ./overleaf/sections/intro.tex
  root_source: this file; several documents include it: ../paper.tex, ../slides.tex
  $ bbtex compile sections/intro.tex 2>/dev/null | grep '^note:'
  note: [bbtex] Several documents include this file (../paper.tex, ../slides.tex): choose one with Configure Document…

A project latexmkrc is read by latexmk; bbtex names the settings it replaces
(output folder, auxiliary folder, engine) and leaves the rest alone. The
auxiliary folder is pinned to the output so results find the log:

  $ export HOME="$PWD/home" XDG_CONFIG_HOME=""
  $ printf "ensure_path('TEXINPUTS', './styles//');  # \$out_dir = 'no';\n\$out_dir = 'rcout';\n\$aux_dir = \"\$out_dir/aux\";\n\$pdf_mode = 5;\n\$pdflatex = 'pdflatex -shell-escape %%O %%S';\n" > latexmkrc
  $ bbtex doctor paper.tex | grep latexmkrc | show
  [INFO] latexmkrc: ./overleaf/latexmkrc: read by latexmk
  [WARN] latexmkrc: ./overleaf/latexmkrc:2: $out_dir is replaced by bbtex's output folder (next to the root file); set output_directory in .bbtex instead
  [WARN] latexmkrc: ./overleaf/latexmkrc:3: $aux_dir is replaced by bbtex's output folder (next to the root file): auxiliary files stay with the output so results and SyncTeX find the log
  [WARN] latexmkrc: ./overleaf/latexmkrc:4: $pdf_mode is replaced by bbtex's engine (pdflatex); choose it with % !TEX program or engine = in .bbtex
  [INFO] latexmkrc: ./overleaf/latexmkrc:5: turns on shell escape for this project's builds
  $ bbtex compile paper.tex 2>/dev/null | grep -E '^(status|note):'
  status: success
  note: [bbtex] latexmkrc $out_dir, $aux_dir, $pdf_mode replaced by bbtex's settings; see LaTeX — Doctor
  $ grep -e '^-outdir' -e '^-auxdir' ../args | show
  -outdir=./overleaf
  -auxdir=./overleaf

Settings that agree with bbtex's aren't flagged, and a user latexmkrc is read too:

  $ printf "\$out_dir = '.';\n\$pdf_mode = 1;\n" > latexmkrc
  $ mkdir -p home && printf "\$aux_dir = 'elsewhere';\n" > home/.latexmkrc
  $ bbtex doctor paper.tex | grep latexmkrc | show
  [INFO] latexmkrc: ~/.latexmkrc: read by latexmk
  [WARN] latexmkrc: ~/.latexmkrc:1: $aux_dir is replaced by bbtex's output folder (next to the root file): auxiliary files stay with the output so results and SyncTeX find the log
  [INFO] latexmkrc: ./overleaf/latexmkrc: read by latexmk
  [OK] latexmkrc: ./overleaf/latexmkrc:1: $out_dir matches bbtex's output folder
  [OK] latexmkrc: ./overleaf/latexmkrc:2: $pdf_mode matches bbtex's engine
  $ bbtex compile paper.tex 2>/dev/null | grep '^note:'
  note: [bbtex] latexmkrc $aux_dir replaced by bbtex's settings; see LaTeX — Doctor
