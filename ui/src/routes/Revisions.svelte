<script>
  // Changes waiting for review: writes to live content from roles that can't
  // publish (agents, authors), held until a person approves them.
  import PageHeader from "../lib/components/PageHeader.svelte";
  import StatusLinks from "../lib/components/StatusLinks.svelte";
  import DataTable from "../lib/components/DataTable.svelte";
  import Cell from "../lib/components/Cell.svelte";
  import Badge from "../lib/components/Badge.svelte";
  import Time from "../lib/components/Time.svelte";
  import EmptyState from "../lib/components/EmptyState.svelte";
  import { get } from "../lib/api.js";
  import { router, go } from "../lib/router.svelte.js";
  const status = router.query.get("status") || "open";
  let list = $state(null);
  get("/revisions?status=" + status).then((r) => (list = r.revisions));
</script>

<PageHeader title="Review" subtitle="Changes to live content from people and agents whose role can't publish. Nothing changes on the site until one is approved." />
<StatusLinks options={[{ label: "Waiting", value: "" }, { label: "Approved", value: "approved" }, { label: "Rejected", value: "rejected" }, { label: "All", value: "all" }]} />
{#if list}
  <DataTable rows={list} onrowclick={(r) => go(`/revisions/${r.id}`)} columns={[{ label: "Change" }, { label: "Fields" }, { label: "From" }, { label: "Status" }, { label: "Proposed" }]}>
    {#snippet row(r)}
      <Cell><a href="#/revisions/{r.id}" class="font-medium text-gray-900 hover:underline">{r.record_label}</a><p class="text-xs text-gray-500">{r.record_type === "CollectionEntry" ? "Entry" : r.record_type} · revision {r.id}</p></Cell>
      <Cell muted>{r.fields.join(", ")}</Cell>
      <Cell>{r.author}</Cell>
      <Cell><Badge status={r.status} /></Cell>
      <Cell muted nowrap><Time value={r.created_at} class="text-xs" /></Cell>
    {/snippet}
    {#snippet empty()}<EmptyState icon="check-circle" title="Nothing waiting">When an agent or author changes something live, it waits here.</EmptyState>{/snippet}
  </DataTable>
{/if}
