---
title: "Working with AI"
summary: "Claude Code, Codex, opencode and any MCP client \u2014 on the content, and on the site."
position: 3
---

This CMS is built to be driven by agents. There are two places an agent
works, and each has its own setup.

## On the content: the `cms` CLI and MCP

Where the agent runs (your machine, usually), install the CLI:

```sh
curl -fsSL {{cms_url}}/agent/install.sh | sh
```

It connects in your browser — you approve the machine, signed in here — and
writes an `AGENTS.md` (and a Claude Code skill) into the directory you ran it
in, telling the agent what this CMS is and how to use `cms`.

Then, to use the CMS from an AI app:

```sh
cms connect
```

It prints the setup for Claude Code, Codex, Claude Desktop, Cursor and any
other app that takes a local MCP server, with this machine's paths filled in,
ready to paste. For Claude Code and Codex that's one command; for the desktop
apps, a few lines of their config. The app then calls every `cms` command as
a tool. With more than one site connected on the machine, `cms connect
--profile <name>` sets each up as its own server.

An app that only takes a URL (a remote connector) can't use it: the server
runs on your machine. Agents that work in a terminal (Codex, opencode and
others) don't need it either: they read `AGENTS.md` and run `cms` directly.

Every answer comes back with what to call next, and `cms commands --json`
is the whole surface in one call. An agent should start with `cms manifest`
(the content model) and `cms brand` (the voice to write in).

## On the site: the site repo's AGENTS.md

In the Astro repo, the CMS's integration (`@librepublish/astro`) keeps an
`AGENTS.md` (and a `CLAUDE.md` pointing at it) up to date on every build —
how the site works with this CMS, and the Site health checks it's held to —
and generates the content model's types. An agent working on templates then
knows that content comes from the CMS, what its JSON looks like, not to
hardcode copy, and what the site must pass.

## What an agent can do

Agents act with a token, and a token can do what its role allows — no more:

- **Your own token** (from `cms login`) carries your role.
- **The Agent role** writes drafts but never publishes: changing live content,
  or publishing, is refused (a 403) until someone who can publish does it.
  Give an unattended agent a service token on that role (Settings › Service
  tokens).
- **With the Approvals plugin**, everything an agent creates, changes or
  deletes through the API waits in Approvals instead: you see what's live
  beside what it proposes, edit it if you like, and approve it to put it live.

The audit log names who (or which token) did what.

## Good habits

- Keep the **brand brief** (Settings › Brand) current: agents read it before
  they write.
- Check an agent's drafts before you publish them, as you would anyone else's.
- Revoke a token you're not using (Settings › Service tokens, or
  `cms service-token revoke <id>`).
