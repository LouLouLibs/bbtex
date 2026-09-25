---
layout: home

hero:
  name: bbtex
  text: LaTeX for BBEdit
  tagline: Hit ⌘K, land on your errors, flip to the PDF and back, and peek at equations without leaving the editor.
  image:
    src: /logo.svg
    alt: bbtex
  actions:
    - theme: brand
      text: Get started
      link: /getting-started
    - theme: alt
      text: About the project
      link: /about
    - theme: alt
      text: GitHub
      link: https://github.com/LouLouLibs/bbtex

features:
  - title: One key to build
    details: ⌘K saves your project, compiles it with latexmk or Tectonic, and lists the errors. Click one and you're on the line.
    link: /project-builds
    linkText: Compiling projects
  - title: Skim, both ways
    details: The PDF follows your cursor without stealing focus, and ⌘-click in Skim takes you back to the source.
    link: /getting-started#skim-inverse-search
    linkText: Set up SyncTeX
  - title: Equation previews
    details: Select some math and see it rendered with your own preamble. It can refresh on save, or follow your selection around.
    link: /selection-preview
    linkText: Previews
  - title: Project outline
    details: Search sections, equations, captions and labels across every included file, then jump straight there.
    link: /project-navigation
    linkText: Navigation
  - title: Citations and references
    details: Search your bibliography by author, title or year, or your labels by context, and drop the key in.
    link: /citation-reference-pickers
    linkText: Pickers
  - title: Environment editing
    details: Change, toggle or wrap environments in one undo. TexLab takes care of completion and Go to Definition.
    link: /bbedit-editing
    linkText: Editing
---

<div class="vp-doc home-tour">

## A quick tour

Press <kbd>⌘</kbd><kbd>K</kbd> and Skim shows the PDF right where your cursor is:

![A compiled paper in Skim](./images/skim-sync.png)

When something breaks, the error lands in BBEdit's results browser, one click
from the line that caused it:

![LaTeX Results listing an undefined control sequence in model.tex, line 7](./images/results-browser.png)

Select an equation to see it rendered with the document's own preamble:

![The preview window showing a rendered display equation](./images/preview-window.png)

## Totally vibe coded

Every line of bbtex, its tests and these docs was written by an AI coding agent
([Claude Code](https://claude.com/claude-code)), with me describing what I
wanted and trying it out in BBEdit. It's well tested, but keep your papers
in version control and [tell me](https://github.com/LouLouLibs/bbtex/issues)
when something looks off. [More about the project →](/about)

</div>
