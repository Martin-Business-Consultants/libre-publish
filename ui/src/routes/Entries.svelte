<script>
  // A collection's entries: status filters, bulk actions, search, the table.
  import PageHeader from "../lib/components/PageHeader.svelte";
  import StatusLinks from "../lib/components/StatusLinks.svelte";
  import SearchBox from "../lib/components/SearchBox.svelte";
  import BulkActions from "../lib/components/BulkActions.svelte";
  import DataTable from "../lib/components/DataTable.svelte";
  import Cell from "../lib/components/Cell.svelte";
  import RowActions from "../lib/components/RowActions.svelte";
  import RowAction from "../lib/components/RowAction.svelte";
  import Pagination from "../lib/components/Pagination.svelte";
  import Badge from "../lib/components/Badge.svelte";
  import Button from "../lib/components/Button.svelte";
  import Time from "../lib/components/Time.svelte";
  import EmptyState from "../lib/components/EmptyState.svelte";
  import { get, post, del } from "../lib/api.js";
  import { router } from "../lib/router.svelte.js";
  import { session } from "../lib/session.svelte.js";
  import { confirm } from "../lib/confirm.svelte.js";
  import { toast, toastError } from "../lib/toast.svelte.js";

  let { params } = $props();
  // svelte-ignore state_referenced_locally
  const slug = params.slug;
  let col = $state(null), list = $state(null), counts = $state({}), selected = $state([]);
  const status = router.query.get("status") || "", q = router.query.get("s") || "", page = Number(router.query.get("page") || 1);
  const canBulk = session.can("entries:publish") || session.can("entries:delete");
  async function load() {
    const p = new URLSearchParams({ per: "50", page: String(page) });
    if (status) p.set("status", status);
    if (q) p.set("q", q);
    const [c, r, ...n] = await Promise.all([
      col ? Promise.resolve({ collection: col }) : get(`/collections/${slug}`),
      get(`/collections/${slug}/entries?${p}`),
      ...["", "draft", "published", "archived"].map((s) => get(`/collections/${slug}/entries?per=1${s ? "&status=" + s : ""}`).then((x) => [s, x.total])),
    ]);
    col = c.collection; list = r; counts = Object.fromEntries(n); selected = [];
  }
  load().catch(toastError);
  async function bulk(action) {
    try {
      if (action === "delete") { const r = await post(`/collections/${slug}/entries/bulk_destroy`, { slugs: selected }); toast(`${r.deleted} moved to the trash.`); }
      else { const r = await post(`/collections/${slug}/entries/bulk_update_status`, { slugs: selected, status: action.replace("status-", "") }); toast(`${r.updated} set to ${r.status}.`); }
      load();
    } catch (e) { toastError(e); }
  }
  async function trash(e) {
    if (!(await confirm({ title: `Move “${e.title}” to the trash?`, message: "It can be restored from the trash.", confirmLabel: "Move to trash", destructive: true }))) return;
    try { await del(`/collections/${slug}/entries/${encodeURIComponent(e.slug)}`); toast("Moved to the trash."); load(); } catch (err) { toastError(err); }
  }
  const statusOptions = $derived([{ label: "All", value: "", count: counts[""] }, ...["published", "draft", "archived"].filter((s) => counts[s]).map((s) => ({ label: s[0].toUpperCase() + s.slice(1), value: s, count: counts[s] }))]);
</script>

<PageHeader title={col?.name || "…"} icon="newspaper" cli="cms entries {slug}">
  {#snippet actions()}
    {#if session.can("collections:write")}<Button href="#/collections/{slug}/settings" icon="settings-outline">Settings</Button>{/if}
    {#if session.can("entries:write")}<Button variant="primary" icon="add" href="#/collections/{slug}/new">Add New</Button>{/if}
  {/snippet}
</PageHeader>
<StatusLinks options={statusOptions} />
<div class="flex flex-wrap items-center justify-between gap-2">
  {#if canBulk}
    <BulkActions noun="entry" count={selected.length} onapply={bulk} actions={[
      ...(session.can("entries:delete") ? [{ value: "delete", label: "Move to trash", destructive: true, confirm: "They go to the trash, where they can be restored." }] : []),
      ...(session.can("entries:publish") ? ["published", "draft", "archived"].map((s) => ({ value: "status-" + s, label: `Set to ${s}` })) : []),
    ]} />
  {:else}<span></span>{/if}
  <SearchBox placeholder="Search entries…" />
</div>
{#if list}
  <DataTable rows={list.entries} key="slug" selectable={canBulk} bind:selected columns={[{ label: "Title" }, { label: "Slug" }, { label: "Category" }, { label: "Status" }, { label: "Locale" }, { label: "Updated" }]}>
    {#snippet row(e)}
      <Cell>
        <a href="#/collections/{slug}/edit/{encodeURIComponent(e.slug)}" class="font-medium text-gray-900 hover:underline">{e.title}</a>
        <RowActions>
          <RowAction href="#/collections/{slug}/edit/{encodeURIComponent(e.slug)}">Edit</RowAction>
          {#if session.can("entries:delete")}<RowAction danger onclick={() => trash(e)}>Trash</RowAction>{/if}
        </RowActions>
      </Cell>
      <Cell mono muted>{e.slug}</Cell>
      <Cell muted>{e.category?.title || "—"}</Cell>
      <Cell><Badge status={e.status} /></Cell>
      <Cell muted>{e.locale}</Cell>
      <Cell muted nowrap><Time value={e.updated_at} class="text-xs" /></Cell>
    {/snippet}
    {#snippet empty()}
      {#if status || q}No entries match.
      {:else}
        <EmptyState icon="newspaper" title="No entries yet">
          {#snippet actions()}{#if session.can("entries:write")}<Button variant="primary" href="#/collections/{slug}/new">Add the first</Button>{/if}{/snippet}
        </EmptyState>
      {/if}
    {/snippet}
  </DataTable>
  <Pagination {page} per={list.per} total={list.total} />
{/if}
