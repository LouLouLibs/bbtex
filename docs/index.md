---
layout: home

hero:
  name: bbtex
  text: LaTeX for BBEdit
  tagline: Compile with one key, jump from errors to source, sync with Skim, and preview equations without leaving the editor.
  image:
    src: /logo.svg
    alt: bbtex
  actions:
    - theme: brand
      text: Get started
      link: /getting-started
    - theme: alt
      text: Command line
      link: /cli
    - theme: alt
      text: GitHub
      link: https://github.com/LouLouLibs/bbtex

features:
  - title: One-key builds
    details: ⌘K saves the project's open inputs, compiles the root with latexmk or Tectonic, and lists errors in BBEdit's results browser. Click an entry to reach the source line.
    link: /project-builds
    linkText: Compiling projects
  - title: Skim, both directions
    details: Successful builds update Skim at the cursor without taking focus. ⌘-click in the PDF to return to the matching line in BBEdit.
    link: /getting-started#skim-inverse-search
    linkText: Set up SyncTeX
  - title: Equation previews
    details: Render selected math with the document's own preamble in a small reusable window. Refresh it on save, or let it follow the selection.
    link: /selection-preview
    linkText: Previews
  - title: Project outline
    details: Search headings, equations, captions and labels across every included file, then jump there. The tree refreshes when you save.
    link: /project-navigation
    linkText: Navigation
  - title: Citations and references
    details: Search the bibliography by author, title or year, or labels by their context, and insert keys into the command at the cursor.
    link: /citation-reference-pickers
    linkText: Pickers
  - title: Structural editing
    details: Change, toggle or wrap environments in one undoable edit. TexLab supplies completion and Go to Definition.
    link: /bbedit-editing
    linkText: Editing
---
