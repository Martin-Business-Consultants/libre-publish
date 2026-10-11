#!/bin/sh
# Libre Publish — local agent setup.
#
#   curl -fsSL __CMS_URL__/agent/install.sh | sh
#
# Installs the `cms` CLI, connects this machine to __SITE__, and writes the
# two files an agent reads to know what it's working with: AGENTS.md in the
# current directory (Claude Code, opencode, Codex, …) and a Claude Code skill.
#
# Everything it writes:
#   ~/.local/bin/cms                    the CLI              (override: CMS_BIN_DIR)
#   ~/.local/share/cms/                 the CLI's Ruby code, and a Ruby to run
#                                       it when the machine has no Ruby 3.4
#   your shell's startup file           ~/.local/bin on PATH, when it isn't
#                                       (skip: CMS_NO_MODIFY_PATH=1)
#   ~/.config/cms/__SITE__.env        URL + token, 0600
#   ~/.config/cms/default               which profile is the default
#   ./AGENTS.md                         created, or appended to if it exists
#   ./.claude/skills/cms/SKILL.md       Claude Code skill    (skip: CMS_SKIP_SKILL=1)
#
# Connecting happens in your browser — nobody copies a token out of a settings
# page and pastes it into a terminal, which is how tokens end up in shell
# history and chat logs. For CI, where there is no browser, pass a token
# instead: USER_AGENT_TOKEN=… sh install.sh
set -eu

CMS_URL="${CMS_URL:-__CMS_URL__}"
CMS_URL="${CMS_URL%/}"
SITE="__SITE__"

BIN_DIR="${CMS_BIN_DIR:-$HOME/.local/bin}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/cms"
PROFILE="${CMS_PROFILE:-$SITE}"
PROFILE_FILE="$CONFIG_DIR/$PROFILE.env"
MARKER="librepublish:cms-agent"

say()  { printf '%s\n' "$*"; }
step() { printf '\n▸ %s\n' "$*"; }
die()  { printf '\ninstall: %s\n' "$*" >&2; exit 1; }

command -v curl >/dev/null 2>&1 || die "curl is required"

# The CLI is one Ruby file, stdlib only, written for Ruby 3.4. A Mac's own
# /usr/bin/ruby is 2.6 and can't read it, and a version manager's shim (mise,
# rbenv, asdf) can be on PATH with no Ruby behind it, so a Ruby is only used
# once it has run and said it's new enough. Without one, a self-contained Ruby
# (Homebrew's portable Ruby: no Homebrew, no admin rights, nothing else
# touched) is fetched into ~/.local/share/cms and checked against its checksum.
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/cms"
PORTABLE_RUBY="3.4.5"

ruby_ok() {
  [ -x "$1" ] && "$1" -e 'exit(Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.4") ? 0 : 1)' >/dev/null 2>&1
}

find_ruby() {
  for candidate in "$DATA_DIR/ruby/bin/ruby" "$(command -v ruby 2>/dev/null || true)" \
      /opt/homebrew/opt/ruby/bin/ruby /usr/local/opt/ruby/bin/ruby \
      "$HOME"/.local/share/mise/installs/ruby/*/bin/ruby "$HOME"/.rbenv/versions/*/bin/ruby \
      "$HOME"/.asdf/installs/ruby/*/bin/ruby; do
    if ruby_ok "$candidate"; then printf '%s\n' "$candidate"; return 0; fi
  done
  return 1
}

sha256_of() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
  else sha256sum "$1" | cut -d' ' -f1
  fi
}

# Prints the fetched Ruby's path; everything else it says goes to stderr.
fetch_ruby() {
  case "$(uname -s) $(uname -m)" in
    "Darwin arm64")  tag="arm64_big_sur"; sum="20fa657858e44a4b39171d6e4111f8a9716eb62a78ebbd1491d94f90bb7b830a" ;;
    "Darwin x86_64") tag="el_capitan";    sum="0c78b38f22fb9b42df6918db00e6f5a80d5b35164f910ffe4c89159326ae98cf" ;;
    "Linux x86_64")  tag="x86_64_linux";  sum="5ea0e3a30feef0743da5a2924c8a71baead1b9f1d571afbd675bc556e59705f5" ;;
    "Linux aarch64"|"Linux arm64") tag="arm64_linux"; sum="58ab194fb0513e8d3f5a3b9a8658cb9909438b405308bf898508eed2b83afc7d" ;;
    *) die "no Ruby 3.4 here, and none to fetch for $(uname -s) $(uname -m). Install Ruby 3.4 or newer and run this again." ;;
  esac
  say "  · no Ruby 3.4 on this machine: fetching one for the CLI (about 12 MB)" >&2
  tmp="$(mktemp -d)"
  curl -fsSL "https://github.com/Homebrew/homebrew-portable-ruby/releases/download/$PORTABLE_RUBY/portable-ruby-$PORTABLE_RUBY.$tag.bottle.tar.gz" \
    -o "$tmp/ruby.tar.gz" || die "couldn't download Ruby"
  [ "$(sha256_of "$tmp/ruby.tar.gz")" = "$sum" ] || die "the Ruby download didn't match its checksum; nothing was installed"
  tar -xzf "$tmp/ruby.tar.gz" -C "$tmp" || die "couldn't unpack Ruby"
  mkdir -p "$DATA_DIR"
  rm -rf "$DATA_DIR/ruby-$PORTABLE_RUBY"
  mv "$tmp/portable-ruby/$PORTABLE_RUBY" "$DATA_DIR/ruby-$PORTABLE_RUBY"
  ln -sfn "ruby-$PORTABLE_RUBY" "$DATA_DIR/ruby"
  rm -rf "$tmp"
  ruby_ok "$DATA_DIR/ruby/bin/ruby" || die "the fetched Ruby doesn't run on this machine"
  printf '%s\n' "$DATA_DIR/ruby/bin/ruby"
}

say "Libre Publish — agent setup"
say "  site:   $SITE"
say "  url:    $CMS_URL"

# ── 1. CLI ──────────────────────────────────────────────────────────────────
step "CLI"
RUBY="$(find_ruby)" || RUBY="$(fetch_ruby)" || exit 1
say "  ✓ Ruby: $RUBY"
mkdir -p "$BIN_DIR" "$DATA_DIR"
curl -fsSL "$CMS_URL/agent/cms" -o "$DATA_DIR/cms.rb" || die "couldn't download the cms CLI"
# The command runs the CLI with that Ruby, whatever PATH holds later (an
# agent's shell, an MCP client's).
cat > "$BIN_DIR/cms" <<EOF
#!/bin/sh
# Libre Publish cms CLI — written by the agent installer.
CMS_BIN="\$0" exec "$RUBY" "$DATA_DIR/cms.rb" "\$@"
EOF
chmod +x "$BIN_DIR/cms"
say "  ✓ $BIN_DIR/cms"

CMS="$BIN_DIR/cms"

# ── 2. Connect ──────────────────────────────────────────────────────────────
step "Connect"
mkdir -p "$CONFIG_DIR"

token="${USER_AGENT_TOKEN:-${CMS_TOKEN:-}}"
if [ -n "$token" ]; then
  # A token supplied up front: CI, or a re-run of a machine that already has
  # one. Verify it rather than writing a credential that turns out to be dead.
  whoami_json="$(curl -sS -H "Authorization: Bearer $token" -H "Accept: application/json" \
    "$CMS_URL/api/api_tokens/me")" || die "couldn't reach $CMS_URL"
  case "$whoami_json" in
    *'"token"'*) ;;
    *'"unauthorized"'*) die "that token was rejected. Rotating in Settings → API token issues a new one." ;;
    *) die "unexpected response from $CMS_URL/api/api_tokens/me: $whoami_json" ;;
  esac

  umask 077
  cat > "$PROFILE_FILE" <<EOF
# Libre Publish — written by the agent installer. Keep this file private.
export CMS_URL="$CMS_URL"
export USER_AGENT_TOKEN="$token"
EOF
  chmod 600 "$PROFILE_FILE"
  [ -f "$CONFIG_DIR/default" ] || printf '%s\n' "$PROFILE" > "$CONFIG_DIR/default"
  say "  ✓ $PROFILE_FILE (0600)"
elif [ -r /dev/tty ]; then
  # Piped into sh, stdin is the script itself — give the CLI the terminal.
  "$CMS" login --url "$CMS_URL" --profile "$PROFILE" < /dev/tty || die "connecting failed"
else
  die "no terminal to approve in, and no token to fall back on. Either run this
  from a terminal, or pass a token:
    USER_AGENT_TOKEN=lp_… sh -c \"\$(curl -fsSL $CMS_URL/agent/install.sh)\""
fi

# ── 3. Check ────────────────────────────────────────────────────────────────
# Answers the question the rest of the setup can't: whether this machine can
# actually do work, or is merely configured.
step "Check"
CMS_PROFILE="$PROFILE" "$CMS" doctor || die "connected, but not ready — see above"

# ── 4. AGENTS.md ────────────────────────────────────────────────────────────
step "AGENTS.md"
agents_md="$(curl -fsSL "$CMS_URL/agent/AGENTS.md")" || die "couldn't download AGENTS.md"
if [ ! -f AGENTS.md ]; then
  printf '%s\n' "$agents_md" > AGENTS.md
  say "  ✓ wrote ./AGENTS.md"
elif grep -q "$MARKER" AGENTS.md 2>/dev/null; then
  say "  · ./AGENTS.md already carries the CMS section — left alone"
  say "    (delete the '$MARKER' block and re-run to refresh it)"
else
  printf '\n' >> AGENTS.md
  printf '%s\n' "$agents_md" >> AGENTS.md
  say "  ✓ appended the CMS section to ./AGENTS.md"
fi
say "    ↳ it reads your Astro repo from the CMS (Settings → GitHub → Frontend repo)"

# ── 5. Claude Code skill ────────────────────────────────────────────────────
if [ "${CMS_SKIP_SKILL:-0}" != "1" ]; then
  step "Claude Code skill"
  mkdir -p .claude/skills/cms
  curl -fsSL "$CMS_URL/agent/SKILL.md" -o .claude/skills/cms/SKILL.md \
    || die "couldn't download SKILL.md"
  say "  ✓ ./.claude/skills/cms/SKILL.md"
  say "    (opencode and Codex read AGENTS.md directly — nothing else to do)"
fi

# ── 6. Done ─────────────────────────────────────────────────────────────────
step "Done"
# A Mac doesn't put ~/.local/bin on PATH; an agent told to run `cms` needs it.
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    line="export PATH=\"$BIN_DIR:\$PATH\""
    case "${SHELL:-}" in
      */zsh)  rc="$HOME/.zshrc" ;;
      */bash) rc="$HOME/.bashrc"; [ "$(uname -s)" = Darwin ] && rc="$HOME/.bash_profile" ;;
      *)      rc="$HOME/.profile" ;;
    esac
    if [ "${CMS_NO_MODIFY_PATH:-0}" = "1" ]; then
      say "  ! $BIN_DIR isn't on your PATH. Add it:"
      say "      $line"
    elif grep -qs "$MARKER-path" "$rc"; then
      say "  · $rc puts $BIN_DIR on PATH; open a new terminal to pick it up"
    else
      printf '\n%s  # %s-path\n' "$line" "$MARKER" >> "$rc"
      say "  ✓ added $BIN_DIR to PATH in $rc; open a new terminal to pick it up"
    fi
    ;;
esac
cat <<EOF

  cms doctor            can this machine do work, and what's stopping it
  cms manifest          the shape of this CMS — read this before writing
  cms commands --json   the whole surface at once, for an agent
  cms help              everything else

  To use it from Claude, Codex, Cursor or another AI app (as MCP tools),
  this prints the setup for each, ready to paste:
      $BIN_DIR/cms connect

Then point your agent at this directory and tell it what to do. It reads
AGENTS.md, pulls your Astro repo from the CMS (asking you for it only if it
isn't recorded there yet), and works from there.
EOF
