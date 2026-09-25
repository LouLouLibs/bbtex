import { defineConfig } from 'vitepress'
import { posix } from 'node:path'
import { fileURLToPath } from 'node:url'
import { readFileSync } from 'node:fs'

// Pages live outside this package, so resolve their imports from site/node_modules.
const modules = fileURLToPath(new URL('../node_modules/', import.meta.url))

const repo = 'https://github.com/LouLouLibs/bbtex'

// One version for the binary and the site: lib/version.ml.
const version = readFileSync(new URL('../../lib/version.ml', import.meta.url), 'utf8').match(/let v = "([^"]+)"/)![1]

// Links from a page to repository files outside docs/ (scripts, tests, the
// README) point at GitHub instead of a missing page.
function repoLinks(md: any) {
  const render = md.renderer.rules.link_open ?? ((t: any, i: number, o: any, _e: any, s: any) => s.renderToken(t, i, o))
  md.renderer.rules.link_open = (tokens: any, idx: number, options: any, env: any, self: any) => {
    const href: string = tokens[idx].attrGet('href') ?? ''
    if (href && !/^[a-z]+:|^#|^\//i.test(href) && env?.relativePath) {
      const target = posix.normalize(posix.join('docs', posix.dirname(env.relativePath), href))
      if (!target.startsWith('docs/')) tokens[idx].attrSet('href', `${repo}/blob/main/${target}`)
      // release-notes.md doubles as the GitHub release body; the site shows it as /changelog.
      else if (target === 'docs/release-notes.md') tokens[idx].attrSet('href', '/changelog')
    }
    return render(tokens, idx, options, env, self)
  }
}

// The pages live in ../docs so they stay readable on GitHub. Internal plans,
// specs and the archived handoff are not published.
export default defineConfig({
  title: 'bbtex',
  description: 'bbtex, a LaTeX package for BBEdit: builds, errors, SyncTeX, equation previews and project navigation.',
  lang: 'en-US',
  base: '/bbtex/',
  srcDir: '../docs',
  srcExclude: ['release-notes.md', 'dev/plans/**', 'dev/specs/**', 'dev/archive/**'],
  cleanUrls: true,
  lastUpdated: true,
  // Development notes link to unpublished plans; those links are fine on GitHub.
  ignoreDeadLinks: [/\/(plans|specs|archive)\//],
  markdown: { config: repoLinks },
  vite: { resolve: { alias: [{ find: /^vue(\/.*)?$/, replacement: `${modules}vue$1` }] } },
  head: [
    ['link', { rel: 'icon', type: 'image/svg+xml', href: '/bbtex/logo.svg' }],
  ],
  themeConfig: {
    version,
    logo: '/logo.svg',
    nav: [
      { text: 'Guide', link: '/getting-started', activeMatch: '^/(about|getting-started|project-builds|bbedit-editing|project-navigation|citation-reference-pickers|selection-preview|setup-troubleshooting)' },
      { text: 'Reference', link: '/cli', activeMatch: '^/(cli|editor-comparison|changelog)' },
      { text: 'Development', link: '/dev/architecture', activeMatch: '^/dev/' },
      {
        text: `v${version}`,
        items: [
          { text: 'Release notes', link: '/changelog' },
          { text: 'Download from GitHub', link: `${repo}/releases` },
        ],
      },
    ],
    sidebar: [
      {
        text: 'Guide',
        items: [
          { text: 'About bbtex', link: '/about' },
          { text: 'Getting started', link: '/getting-started' },
          { text: 'Compiling projects', link: '/project-builds' },
          { text: 'Writing and editing', link: '/bbedit-editing' },
          { text: 'Project outline', link: '/project-navigation' },
          { text: 'Citations and references', link: '/citation-reference-pickers' },
          { text: 'Equation previews', link: '/selection-preview' },
          { text: 'Troubleshooting', link: '/setup-troubleshooting' },
        ],
      },
      {
        text: 'Reference',
        items: [
          { text: 'Command line', link: '/cli' },
          { text: 'vs TeXShop, LaTeXTools, AUCTeX', link: '/editor-comparison' },
          { text: 'Release notes', link: '/changelog' },
        ],
      },
      {
        text: 'Development',
        collapsed: true,
        items: [
          { text: 'Architecture', link: '/dev/architecture' },
          { text: 'CI and releases', link: '/dev/releases' },
          { text: 'Real-engine coverage', link: '/dev/real-engine-regressions' },
          { text: 'Outline window notes', link: '/dev/outline-window' },
          { text: 'Project status', link: '/dev/HANDOFF' },
        ],
      },
    ],
    outline: { level: [2, 3], label: 'Contents' },
    search: { provider: 'local' },
    socialLinks: [{ icon: 'github', link: 'https://github.com/LouLouLibs/bbtex' }],
    footer: {
      message: 'MIT licensed. Vibe coded with Claude Code. Part of <a href="https://github.com/LouLouLibs">LouLouLibs</a>.',
      copyright: '© 2025–2026 Erik Loualiche',
    },
  },
})
