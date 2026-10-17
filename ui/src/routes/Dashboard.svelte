<script>
  // The dashboard (the Rails admin's): Content as cards (pages, each
  // collection, globals), working through the API, what waits for review,
  // site health, and recent activity.
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
  import { plural } from "../lib/format.js";

  let data = $state(null);
  async function load() {
    const [m, health, revisions, audit, tokens] = await Promise.all([
      get("/manifest"),
      get("/site_health").catch(() => null),
      get("/revisions").catch(() => ({ revisions: [] })),
      session.can("audit_log:read") ? get("/audit_log?per=8").catch(() => null) : null,
      session.can("settings:read") ? get("/service_tokens").catch(() => null) : null,
    ]);
    data = { m, health, revisions: revisions.revisions, audit: audit?.audit_logs || [], tokens: tokens?.service_tokens || [] };
  }
  load();
  async function seed() {
    try { const r = await post("/block_types/seed"); toast(`Installed ${r.count} block types.`); blockTypes.load(true); load(); } catch (e) { toastError(e); }
  }
  const icons = ["newspaper", "quote", "marker", "tag", "calendar", "briefcase", "chef-hat", "megaphone", "lightbulb"];
  const recentTokens = $derived((data?.tokens || []).filter((t) => t.last_used_at && Date.now() - new Date(t.last_used_at) < 7 * 864e5));
</script>

<PageHeader title="Dashboard" cli="cms doctor" />

{#if !data}
  <div class="flex justify-center py-16"><Spinner /></div>
{:else}
  {@const c = data.m.counts}
  <section class="flex flex-col gap-3">
    <h2 class="text-base font-semibold text-gray-900">Content</h2>
    <div class="grid grid-cols-2 gap-3 lg:grid-cols-3 xl:grid-cols-4">
      {#snippet card(href, icon, name, line)}
        <a {href} class="flex items-center gap-3 rounded-xl border border-gray-200 bg-surface p-4 hover:border-gray-300 hover:bg-gray-50">
          <span class="flex size-9 shrink-0 items-center justify-center rounded-md bg-gray-100 text-gray-600"><Icon name={icon} /></span>
          <span class="min-w-0"><span class="block truncate font-medium text-gray-900">{name}</span><span class="block text-xs text-gray-500">{line}</span></span>
        </a>
      {/snippet}
      {@render card("#/pages", "document", "Pages", plural(c.pages, "page"))}
      {#each data.m.collections as col, i}
        {@render card(`#/collections/${col.slug}`, icons[i % icons.length], col.name, plural(col.entry_count, "entry", "entries"))}
      {/each}
      {@render card("#/globals", "world", "Globals", plural(c.globals, "global"))}
    </div>
  </section>

  {#if c.block_types === 0 && session.can("block_types:write")}
    <Notice tone="info">
      <div class="flex flex-wrap items-center justify-between gap-3">
        <span><strong class="font-semibold">Start with the starter blocks.</strong> Pages are built from block types: a hero, text, an image, a list of entries and 18 more.</span>
        <Button variant="primary" size="sm" onclick={seed}>Install them</Button>
      </div>
    </Notice>
  {/if}

  <div class="grid items-start gap-6 lg:grid-cols-2">
    <Panel>
      {#snippet header()}<h2 class="flex items-center gap-2 text-base font-semibold text-gray-900"><Icon name="ai" class="text-gray-400" />Working through the API</h2>{/snippet}
      {#snippet actions()}{#if session.can("settings:read")}<Button size="sm" href="#/settings/tokens">Service tokens</Button>{/if}{/snippet}
      <div class="flex flex-col gap-3 p-5 text-sm text-gray-700">
        {#if recentTokens.length}
          <p>{plural(recentTokens.length, "token")} used the API this week: {recentTokens.map((t) => t.name).join(", ")}.</p>
        {:else}<p>No token has used the API this week.</p>{/if}
        <p class="text-xs text-gray-500">Drive this CMS from an agent: <code class="rounded-sm bg-gray-100 px-1 font-mono">cms login --url {location.origin}</code>, then <code class="rounded-sm bg-gray-100 px-1 font-mono">cms manifest</code> to see its shape.</p>
      </div>
    </Panel>

    <div class="flex flex-col gap-6">
      {#if data.revisions.length}
        <Panel title="Waiting for review">
          {#snippet actions()}<Button size="sm" href="#/revisions">Review</Button>{/snippet}
          <ul class="divide-y divide-gray-100">
            {#each data.revisions.slice(0, 5) as r}
              <li class="flex items-center justify-between gap-4 px-5 py-2.5 text-sm">
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

  {#if data.audit.length}
    <Panel title="Recent activity">
      {#snippet actions()}<Button size="sm" href="#/audit">Audit log</Button>{/snippet}
      <ul class="divide-y divide-gray-100">
        {#each data.audit as l}
          <li class="flex items-center justify-between gap-4 px-5 py-2.5 text-sm">
            <span class="flex min-w-0 items-center gap-2"><span class="shrink-0 text-gray-900">{l.actor.label}</span><Badge>{l.action}</Badge><span class="truncate text-gray-700">{l.target.label}</span></span>
            <Time value={l.created_at} class="shrink-0 text-xs text-gray-500" />
          </li>
        {/each}
      </ul>
    </Panel>
  {/if}
{/if}
