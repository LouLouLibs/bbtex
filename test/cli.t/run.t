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
