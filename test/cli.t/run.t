Arguments after a command that takes free text are data, not options: a
search for "-h" or "--verbose" searches for it.

  $ printf '\\section{Methods}\\label{sec:methods}\n\\section{Results}\n' > main.tex

  $ bbtex outline main.tex | grep -o '"kind":"[a-z]*"' | sort
  "kind":"label"
  "kind":"section"
  "kind":"section"

  $ bbtex outline main.tex -h | grep -c Usage
  0
  [1]

  $ bbtex outline main.tex --verbose | grep -c '"kind"'
  0
  [1]

  $ bbtex outline main.tex Results | grep -o '"title":"[A-Za-z]*"'
  "title":"Results"

Options still work before the command, and for compile-style commands.

  $ bbtex --help | head -1
  Usage: bbtex <command> [options] <file>

  $ bbtex paths --engine xelatex main.tex | grep '^engine'
  engine: xelatex

forward-search reports when SyncTeX has no position for a file (here one that
is not part of the PDF) instead of claiming page 1; the PDF is still given.

  $ printf '\\documentclass{article}\n\\begin{document}\nHello\n\\end{document}\n' > doc.tex
  $ printf '%%!TEX root = doc.tex\nNot included.\n' > orphan.tex
  $ pdflatex -synctex=1 -interaction=nonstopmode doc.tex > /dev/null
  $ bbtex forward-search orphan.tex 2 2>/dev/null | sed 's|^pdf: .*/|pdf: |'
  status: no-position
  pdf: doc.pdf
  message: No SyncTeX position for line 2

preview-fragment rejects incomplete selections before compiling.

  $ printf '\\documentclass{article}\n\\begin{document}\nx\n\\end{document}\n' > frag.tex
  $ mkdir frag && printf 'Intro ' > frag/prefix && printf '\\frac{a}{b' > frag/selected
  $ bbtex preview-fragment frag.tex frag
  status: invalid
  message: Selection has unbalanced braces or environments.
  [5]
  $ printf '  ' > frag/selected
  $ bbtex preview-fragment frag.tex frag
  status: empty
  [6]

The version matches lib/version.ml.

  $ bbtex --version
  bbtex 0.1.0

parse-log keeps TeX's message and adds a [bbtex] hint under the ones it
recognises; unrecognised errors get none.

  $ printf '(./model.tex\n./model.tex:7: Undefined control sequence.\nl.7 Hello \\foo\n               world.\n\n./model.tex:9: Emergency stop.\nl.9 \\end\n)\n' > model.log
  $ bbtex parse-log --format bbedit model.log
  ./model.tex:7: error: Undefined control sequence.
  ./model.tex:7: note: [bbtex] A command isn't defined: check for a typo, or a missing \usepackage.
  ./model.tex:9: error: Emergency stop.
  2 error(s), 0 warning(s), 0 bad box(es)
  [1]
  $ bbtex parse-log model.log 2>&1 | sed 's/\x1b\[[0-9;]*m//g'
  error in ./model.tex:7
    Undefined control sequence.
    | Hello \foo
    [bbtex] A command isn't defined: check for a typo, or a missing \usepackage.
  error in ./model.tex:9
    Emergency stop.
    | \end
  2 error(s), 0 warning(s), 0 bad box(es)
