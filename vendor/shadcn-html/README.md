# shadcn-html

The admin's design system: https://shadcn-html.com (MIT, LICENSE), by Cody
Lindley. Copied as published, from `dist/` of
https://github.com/codylindley/shadcn-html at `main`, commit
0964e09e16034e39a244589d457a866171991f1d (v0.7.13-alpha, 2026-04-19):

- `theme/default-semantic-tokens.css`: the tokens (`--background`,
  `--primary`, `--radius`, …), light on `:root` and dark on `.dark`.
- `components/<name>/<name>.css`: each component's stylesheet, in
  `@layer components`.
- `components/<name>/component-skill.md`: each component's markup, variants
  and ARIA, the reference for writing it.

Its JavaScript isn't copied: the admin's Stimulus controllers do what the
components' scripts would (they set themselves up with a MutationObserver
and a `data-init` mark, which Turbo's morphing strips). Don't edit these
files: `_global.css` maps Settings › Branding onto the tokens, and an
update is a fresh copy of `dist/` at a newer commit.
