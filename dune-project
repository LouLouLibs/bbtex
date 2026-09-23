(lang dune 3.0)
(name bbtex)
(generate_opam_files true)
(license MIT)
(authors "Erik Loualiche")
(maintainers "Erik Loualiche")
(source (github LouLouLibs/bbtex))

(package
 (name bbtex)
 (synopsis "LaTeX builds, diagnostics and navigation for BBEdit")
 (description
  "The bbtex command-line tool behind the bbtex BBEdit package: compiles LaTeX projects, parses logs into BBEdit results, and powers SyncTeX, previews, the project outline and citation/reference pickers.")
 (depends
  (ocaml (>= 4.14))
  (uucp (>= 17.0.0))
  (uunf (>= 17.0.0))))
