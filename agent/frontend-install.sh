#!/bin/sh
# Libre Publish — connect an Astro site to __SITE__.
#
#   curl -fsSL __CMS_URL__/frontend/install.sh | sh
#
# Run it in an Astro project (its root, or its src/ directory). It:
#
#   package.json   adds @librepublish/astro — Forms and Media, the CMS's default
#                  plugins, are part of it, and Commerce's <QuoteRequest> (npm,
#                  pnpm, yarn or bun: whichever the project uses)
#   .env           CMS_BASE_URL and CMS_API_TOKEN (kept out of git)
#
# and prints what to add to astro.config if cms() isn't there yet. The
# integration lives at github.com/Martin-Business-Consultants/libre-cms-astro
# and installs from there (LIBREPUBLISH_ASTRO=… installs another source, e.g.
# a tag: github:Martin-Business-Consultants/libre-cms-astro#v0.1.1).
#
# The token is the site's own read-only service token, approved in your
# browser — nobody copies one out of a settings page. For CI, pass one
# instead: CMS_API_TOKEN=lps_… sh -c "$(curl -fsSL __CMS_URL__/frontend/install.sh)"
#
# Then `npx astro dev` writes AGENTS.md (how this site works with the CMS,
# and the Site health checks it's held to). Re-running is safe: it updates
# the packages and .env and leaves everything else alone.
set -eu

CMS_URL="${CMS_URL:-__CMS_URL__}"
CMS_URL="${CMS_URL%/}"
SITE="__SITE__"

ASTRO="${LIBREPUBLISH_ASTRO:-github:Martin-Business-Consultants/libre-cms-astro}"

for arg in "$@"; do
  case "$arg" in
    # Commerce is part of @librepublish/astro now; kept so old commands still run.
    --commerce|--no-commerce|--forms|--no-forms) ;;
    *) printf 'install: unknown option %s\n' "$arg" >&2; exit 1 ;;
  esac
done

say()  { printf '%s\n' "$*"; }
step() { printf '\n▸ %s\n' "$*"; }
die()  { printf '\ninstall: %s\n' "$*" >&2; exit 1; }

command -v curl >/dev/null 2>&1 || die "curl is required"
command -v node >/dev/null 2>&1 || die "node is required (an Astro project has it)"

# ── 1. Find the project ─────────────────────────────────────────────────────
# The directory with astro.config.*: here, or up to three levels above (so
# running it from src/ works).
find_root() {
  dir="$PWD"
  for _ in 1 2 3 4; do
    for ext in mjs ts mts js cjs; do
      if [ -f "$dir/astro.config.$ext" ]; then ROOT="$dir"; CONFIG="$dir/astro.config.$ext"; return 0; fi
    done
    [ "$dir" = "/" ] && break
    dir="$(dirname "$dir")"
  done
  return 1
}
find_root || die "no astro.config.* here or above — run this inside an Astro project"
NAME="$(node -e 'try{console.log(require(process.argv[1]).name||"")}catch{console.log("")}' "$ROOT/package.json")"
NAME="${NAME:-$(basename "$ROOT")}"

say "Libre Publish — connect an Astro site"
say "  cms:     $CMS_URL ($SITE)"
say "  project: $ROOT"

# ── 2. Connect ──────────────────────────────────────────────────────────────
step "Connect"
# A value from JSON on stdin by dotted path; a list comes out comma-separated.
json() { node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const v=process.argv[1].split(".").reduce((o,k)=>o?.[k],JSON.parse(s));console.log(Array.isArray(v)?v.join(","):(v??""))}catch{console.log("")}})' "$1"; }

token="${CMS_API_TOKEN:-}"
if [ -z "$token" ] && [ -f "$ROOT/.env" ]; then
  token="$(sed -n 's/^CMS_API_TOKEN=//p' "$ROOT/.env" | tail -1)"
fi

if [ -n "$token" ]; then
  say "  · using the token already given"
elif [ -r /dev/tty ]; then
  code_json="$(curl -fsS -X POST "$CMS_URL/api/device/code" \
    --data-urlencode "purpose=site" --data-urlencode "label=$NAME" --data-urlencode "hostname=$(hostname 2>/dev/null || echo site)")" \
    || die "couldn't reach $CMS_URL"
  device_code="$(printf '%s' "$code_json" | json device_code)"
  user_code="$(printf '%s' "$code_json" | json user_code)"
  url="$(printf '%s' "$code_json" | json verification_url)"
  interval="$(printf '%s' "$code_json" | json interval)"
  [ -n "$device_code" ] || die "unexpected response from the CMS: $code_json"

  say "  Approve this site in your browser (signed in to the CMS):"
  say "      $url"
  say "  and check it shows the code  $user_code"
  (command -v open >/dev/null 2>&1 && open "$url") || (command -v xdg-open >/dev/null 2>&1 && xdg-open "$url") || true

  tries=0
  while :; do
    sleep "${interval:-3}"
    tries=$((tries + 1))
    [ "$tries" -gt 300 ] && die "gave up waiting for approval"
    status="$(curl -sS -o /tmp/cms-device-$$ -w '%{http_code}' -X POST "$CMS_URL/api/device/token" --data-urlencode "device_code=$device_code")"
    case "$status" in
      202) ;;
      200) token="$(json token < /tmp/cms-device-$$)"; rm -f /tmp/cms-device-$$; break ;;
      403) rm -f /tmp/cms-device-$$; die "approval was denied" ;;
      *) rm -f /tmp/cms-device-$$; die "the code expired — run this again" ;;
    esac
  done
  say "  ✓ approved: the site has a read-only service token of its own"
else
  die "no terminal to approve in, and no token. Pass one:
    CMS_API_TOKEN=lps_… sh -c \"\$(curl -fsSL $CMS_URL/frontend/install.sh)\""
fi

# The delivery API the site reads (/api/v1), to check the token works.
check="$(curl -sS -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $token" "$CMS_URL/api/v1/site")"
[ "$check" = "200" ] || die "the CMS refused that token ($check)"

env_file="$ROOT/.env"
touch "$env_file"
grep -v '^CMS_BASE_URL=\|^CMS_API_TOKEN=' "$env_file" > "$env_file.tmp" || true
{ cat "$env_file.tmp"; printf 'CMS_BASE_URL=%s\nCMS_API_TOKEN=%s\n' "$CMS_URL" "$token"; } > "$env_file"
rm -f "$env_file.tmp"
chmod 600 "$env_file"
if [ ! -f "$ROOT/.gitignore" ] || ! grep -qx '.env' "$ROOT/.gitignore"; then
  printf '.env\n' >> "$ROOT/.gitignore"
fi
say "  ✓ .env (CMS_BASE_URL, CMS_API_TOKEN) — kept out of git"

# ── 3. Packages ─────────────────────────────────────────────────────────────
step "Packages"
packages="@librepublish/astro@$ASTRO"

if [ -f "$ROOT/pnpm-lock.yaml" ]; then add="pnpm add"
elif [ -f "$ROOT/yarn.lock" ]; then add="yarn add"
elif [ -f "$ROOT/bun.lockb" ] || [ -f "$ROOT/bun.lock" ]; then add="bun add"
else add="npm install"; fi
say "  \$ $add $packages"
(cd "$ROOT" && $add $packages) || die "couldn't install $packages"
say "  ✓ $packages"

# ── 4. astro.config ─────────────────────────────────────────────────────────
step "astro.config"
if grep -q "@librepublish/astro\"\|@librepublish/astro'" "$CONFIG"; then
  say "  · $(basename "$CONFIG") already uses @librepublish/astro — left alone"
else
  say "  Add the integration to $(basename "$CONFIG"):"
  say ""
  say '      import cms from "@librepublish/astro";'
  say ""
  say '      export default defineConfig({ integrations: [cms()] });'
  say ""
  say "  Forms, Media and Commerce come with it: <Form slug>, <Image> and"
  say '  <QuoteRequest items> from "@librepublish/astro/components/*.astro".'
  say ""
  say "  On Cloudflare, with pages rendered on demand, add the adapter too:"
  say '      import cloudflare from "@astrojs/cloudflare";'
  say '      adapter: cloudflare({ prerenderEnvironment: "node" }),'
fi

# ── 5. Done ─────────────────────────────────────────────────────────────────
step "Done"
cat <<EOF
  Set the same two variables where the site builds and runs (Cloudflare's
  build settings and the Worker's variables, or the repo's secrets).

  Content comes in through the loaders — src/content.config.ts:

      import { defineCollection } from "astro:content";
      import { cmsPages, cmsEntries, cmsGlobals, cmsAssets } from "@librepublish/astro/loaders";
      export const collections = {
        pages: defineCollection({ loader: cmsPages() }),
        globals: defineCollection({ loader: cmsGlobals() }),
        assets: defineCollection({ loader: cmsAssets() }),
      };

  npx astro dev     writes AGENTS.md (how this site works with the CMS, and
                    the Site health checks it's held to) — commit it
  npx astro build   writes _redirects, adds sitemap.xml and robots.txt,
                    checks Site health, and reports the build to the CMS
EOF
