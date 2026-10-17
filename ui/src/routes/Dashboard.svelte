<script>
  // The dashboard (dashboard.css): counts as cards, what changed lately,
  // what waits for review, and site health.
  import PageHeader from "../lib/components/PageHeader.svelte";
  import Panel from "../lib/components/Panel.svelte";
  import Badge from "../lib/components/Badge.svelte";
  import Button from "../lib/components/Button.svelte";
  import Icon from "../lib/components/Icon.svelte";
  import Time from "../lib/components/Time.svelte";
  import Notice from "../lib/components/Notice.svelte";
  import Spinner from "../lib/components/Spinner.svelte";
  import { get, post } from "../lib/api.js";
  import { session } from "../lib/session.svelte.js";
  import { toast, toastError } from "../lib/toast.svelte.js";
  import { blockTypes } from "../lib/blocks.svelte.js";

  let data = $state(null);
  async function load() {
    const [m, pages, health, revisions] = await Promise.all([
      get("/manifest"),
      session.can("pages:read") ? get("/pages?per=6") : { pages: [] },
      get("/site_health").catch(() => null),
      get("/revisions").catch(() => ({ revisions: [] })),
    ]);
    data = { m, pages: pages.pages, health, revisions: revisions.revisions };
  }
  load();
  async function seed() {
    try { const r = await post("/block_types/seed"); toast(`Installed ${r.count} block types.`); blockTypes.load(true); load(); } catch (e) { toastError(e); }
  }
  const hello = () => { const h = new Date().getHours(); return h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening"; };
</script>

<PageHeader title="Dashboard" subtitle="{hello()}, {(session.me.user.name || '').split(' ')[0]}." />

{#if !data}
  <div class="flex justify-center py-16"><Spinner /></div>
{:else}
  {@const c = data.m.counts}
  <div class="grid grid-cols-2 gap-3 lg:grid-cols-3 xl:grid-cols-5">
    {#each [["Pages", c.pages, "#/pages", "document"], ["Entries", c.entries, "#/collections", "newspaper"], ["Collections", c.collections, "#/collections", "stack"], ["Globals", c.globals, "#/globals", "world"], ["Block types", c.block_types, "#/blocks", "grid"]] as [label, n, href, icon]}
      <a {href} class="group flex flex-col gap-3 rounded-xl border border-gray-200 bg-surface p-5 hover:border-gray-300 hover:bg-gray-50">
        <span class="flex items-center justify-between text-xs font-medium uppercase tracking-wide text-gray-500">{label}<Icon name={icon} class="text-gray-300 group-hover:text-gray-400" /></span>
        <span class="text-3xl font-bold tabular-nums tracking-tight text-gray-900">{n}</span>
      </a>
    {/each}
  </div>

  {#if c.block_types === 0 && session.can("block_types:write")}
    <Notice tone="info">
      <div class="flex flex-wrap items-center justify-between gap-3">
        <span><strong class="font-semibold">Start with the starter blocks.</strong> Pages are built from block types: a hero, text, an image, a list of entries and 18 more.</span>
        <Button variant="primary" size="sm" onclick={seed}>Install them</Button>
      </div>
    </Notice>
  {/if}

  <div class="grid items-start gap-6 lg:grid-cols-2">
    <Panel title="Recently updated">
      {#snippet actions()}<Button variant="plain" size="sm" href="#/pages">All pages</Button>{/snippet}
      {#if data.pages.length}
        <ul class="divide-y divide-gray-100">
          {#each data.pages as p}
            <li class="flex items-center justify-between gap-4 px-5 py-2.5">
              <a href="#/pages/edit/{encodeURIComponent(p.path)}" class="min-w-0 truncate font-medium text-gray-900 hover:underline">{p.title}<span class="ml-2 font-mono text-xs font-normal text-gray-400">/{p.path}</span></a>
              <span class="flex shrink-0 items-center gap-3 text-xs text-gray-500"><Badge status={p.status} /><Time value={p.updated_at} /></span>
            </li>
          {/each}
        </ul>
      {:else}
        <div class="px-5 py-8 text-center text-sm text-gray-500">No pages yet. <a href="#/pages/new" class="font-medium text-accent-600 hover:underline">Make the first one</a>, usually the home page.</div>
      {/if}
    </Panel>

    <div class="flex flex-col gap-6">
      {#if data.revisions.length}
        <Panel title="Waiting for review">
          {#snippet actions()}<Badge tone="warning">{data.revisions.length}</Badge>{/snippet}
          <ul class="divide-y divide-gray-100">
            {#each data.revisions.slice(0, 5) as r}
              <li class="flex items-center justify-between gap-4 px-5 py-2.5">
                <a href="#/revisions/{r.id}" class="min-w-0 truncate font-medium text-gray-900 hover:underline">{r.record_label}</a>
                <span class="shrink-0 text-xs text-gray-500">{r.author} · <Time value={r.created_at} /></span>
              </li>
            {/each}
          </ul>
        </Panel>
      {/if}
      {#if data.health}
        <Panel title="Site health">
          {#snippet actions()}{#if data.health.failing}<Badge tone="danger">{data.health.failing} failing</Badge>{:else}<Badge tone="success">All good</Badge>{/if}{/snippet}
          <ul class="divide-y divide-gray-100">
            {#each data.health.checks as ch}
              <li class="flex items-start gap-3 px-5 py-2.5 text-sm">
                <Icon name={ch.state === "passes" ? "check-circle" : ch.state === "fails" ? "close-circle" : "help-circle"} size="md" class={ch.state === "passes" ? "text-green-600" : ch.state === "fails" ? "text-red-600" : "text-yellow-600"} />
                <span class="text-gray-700">{ch.message}</span>
              </li>
            {/each}
          </ul>
        </Panel>
      {/if}
    </div>
  </div>
{/if}
