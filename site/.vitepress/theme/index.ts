import DefaultTheme from 'vitepress/theme'
import { h } from 'vue'
import { useData, withBase } from 'vitepress'
import './custom.css'

// A release badge above the home hero title, from themeConfig.version.
function ReleaseBadge() {
  const { theme } = useData()
  return h('a', { class: 'release-badge', href: withBase('/changelog') }, [
    h('span', { class: 'release-badge-version' }, `v${theme.value.version}`),
    h('span', 'first release · totally vibe coded'),
  ])
}

export default {
  extends: DefaultTheme,
  Layout: () => h(DefaultTheme.Layout, null, { 'home-hero-info-before': () => h(ReleaseBadge) }),
}
