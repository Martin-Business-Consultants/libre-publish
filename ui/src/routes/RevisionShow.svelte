<script>
  // One proposed change: each field as it's live now beside what's proposed,
  // and Approve (applied as the approver) or Reject, with a note.
  import PageHeader from "../lib/components/PageHeader.svelte";
  import Panel from "../lib/components/Panel.svelte";
  import Badge from "../lib/components/Badge.svelte";
  import Button from "../lib/components/Button.svelte";
  import Input from "../lib/components/Input.svelte";
  import Notice from "../lib/components/Notice.svelte";
  import Time from "../lib/components/Time.svelte";
  import Spinner from "../lib/components/Spinner.svelte";
  import { get, post } from "../lib/api.js";
  import { site } from "../lib/site.svelte.js";
  import { toast, toastError } from "../lib/toast.svelte.js";
  import { go } from "../lib/router.svelte.js";
  let { params } = $props();
  let r = $state(null), live = $state(null), note = $state(""), busy = $state("");
  async function load() {
    r = (await get(`/revisions/${params.id}`)).revision;
    try {
      if (r.record_type === "Page") { const p = (await get("/pages?per=100")).pages.find((x) => x.id === r.record_id); if (p) live = (await get(`/pages/${p.path}`)).page; }
      if (r.record_type === "Global") { const g = (await get("/globals")).globals.find((x) => x.id === r.record_id); if (g) live = g; }
      if (r.record_type === "CollectionEntry") {
        for (const c of site.collections) {
          const e = (await get(`/collections/${c.slug}/entries?per=100`)).entries.find((x) => x.id === r.record_id);
          if (e) { live = (await get(`/collections/${c.slug}/entries/${e.slug}`)).entry; break; }
        }
      }
    } catch {}
  }
  load().catch(toastError);
  async function decide(what) {
    busy = what;
    try { await post(`/revisions/${r.id}/${what}`, { note }); toast(what === "approve" ? "Approved: the change is live." : "Rejected."); go("/revisions"); }
    catch (e) { toastError(e); }
    busy = "";
  }
  const show = (v) => (v == null ? "—" : typeof v === "string" ? v : JSON.stringify(v, null, 2));
</script>

{#if !r}
  <div class="flex justify-center py-16"><Spinner /></div>
{:else}
  <a href="#/revisions" class="text-sm text-gray-500 hover:text-gray-900">← Review</a>
  <PageHeader title={r.record_label} subtitle="Revision {r.id}">
    {#snippet actions()}<Badge status={r.status} />{/snippet}
  </PageHeader>
  <p class="text-sm text-gray-600">Proposed by <strong class="font-semibold text-gray-900">{r.author}</strong> <Time value={r.created_at} />.{#if r.note} Note: “{r.note}”{/if}</p>
  {#each r.fields as f}
    <Panel title={f}>
      <div class="grid gap-2 p-5 sm:grid-cols-2">
        <div class="flex flex-col gap-1"><span class="text-xs font-medium uppercase tracking-wide text-gray-500">Live now</span>
          <pre class="max-h-96 overflow-auto whitespace-pre-wrap break-words rounded-md bg-red-50 p-3 font-mono text-xs text-red-800">{live ? show(live[f]) : "…"}</pre></div>
        <div class="flex flex-col gap-1"><span class="text-xs font-medium uppercase tracking-wide text-gray-500">Proposed</span>
          <pre class="max-h-96 overflow-auto whitespace-pre-wrap break-words rounded-md bg-green-50 p-3 font-mono text-xs text-green-800">{show(r.changes[f])}</pre></div>
      </div>
    </Panel>
  {/each}
  {#if r.status === "open"}
    <div class="sticky bottom-4 flex flex-wrap items-center gap-2 rounded-xl border border-gray-200 bg-surface p-3 shadow-overlay">
      <div class="min-w-48 flex-1"><Input bind:value={note} placeholder="A note for whoever proposed it (optional)" /></div>
      <Button variant="danger" loading={busy === "reject"} onclick={() => decide("reject")}>Reject</Button>
      <Button variant="primary" icon="check" loading={busy === "approve"} onclick={() => decide("approve")}>Approve and publish</Button>
    </div>
  {:else}
    <Notice tone={r.status === "approved" ? "success" : "warning"}>This change was {r.status} <Time value={r.decided_at} />.</Notice>
  {/if}
{/if}
