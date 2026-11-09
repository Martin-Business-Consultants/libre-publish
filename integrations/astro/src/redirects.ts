/**
 * Redirects live in the CMS (Tools › Redirects) and nowhere else: after a
 * build, `_redirects` holds the CMS's rules (GET /api/v1/redirects.txt, a
 * Cloudflare _redirects file) and only those. A site that defines its own —
 * astro.config's `redirects`, or rules in public/_redirects — stops the build,
 * since two places to keep a redirect means one goes stale.
 */
export const REDIRECTS_LIVE_IN_THE_CMS =
  "Redirects live in the CMS (Tools › Redirects), not in the site. Move them there and remove them from the site";

/** The rules a _redirects file holds, ignoring comments and blank lines. */
export function redirectRules(text: string): string[] {
  return text.split("\n").map((line) => line.trim()).filter((line) => line && !line.startsWith("#"));
}
