<script>
  // All pages (pages/index): status filters with counts, the locale filter,
  // bulk actions and search, the tree in a table with row actions.
  import PageHeader from "../lib/components/PageHeader.svelte";
  import StatusLinks from "../lib/components/StatusLinks.svelte";
  import QuickFilter from "../lib/components/QuickFilter.svelte";
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
  import { get, post, del, pagePath } from "../lib/api.js";
  import { router } from "../lib/router.svelte.js";
  import { session } from "../lib/session.svelte.js";
  import { site } from "../lib/site.svelte.js";
  import { confirm } from "../lib/confirm.svelte.js";
  import { toast, toastError } from "../lib/toast.svelte.js";

  let list = $state(null), counts = $state({}), locales = $state([]), selected = $state([]);
  const status = router.query.get("status") || "";
  const locale = router.query.get("locale") || "";
  const q = router.query.get("s") || "";
  const page = Number(router.query.get("page") || 1);
  const canBulk = session.can("pages:publish") || session.can("pages:delete");

  async function load() {
    const params = new URLSearchParams({ per: "50", page: String(page), sort: q ? "updated" : "path" });
    if (status) params.set("status", status);
    if (locale) params.set("locale", locale);
    if (q) params.set("q", q);
    const [r, ...c] = await Promise.all([
      get("/pages?" + params),
      ...["", "draft", "published", "archived"].map((s) => get(`/pages?per=1${s ? "&status=" + s : ""}`).then((x) => [s, x.total])),
    ]);
    list = r; counts = Object.fromEntries(c);
    if (!locales.length) locales = [...new Set((await get("/pages?per=100")).pages.map((p) => p.locale))];
    selected = [];
  }
  load();

  async function bulk(action) {
    try {
      if (action === "delete") { const r = await post("/pages/bulk_destroy", { slugs: selected }); toast(`${r.deleted} moved to the trash.`); }
      else { const r = await post("/pages/bulk_update_status", { slugs: selected, status: action.replace("status-", "") }); toast(`${r.updated} set to ${r.status}.`); }
      load();
    } catch (e) { toastError(e); }
  }
  async function trash(p) {
    if (!(await confirm({ title: `Move “${p.title}” to the trash?`, message: "Its child pages go with it. It can be restored from the trash.", confirmLabel: "Move to trash", destructive: true }))) return;
    try { await del(`/pages/${pagePath(p.path)}`); toast("Moved to the trash."); load(); } catch (e) { toastError(e); }
  }
  const statusOptions = $derived([{ label: "All", value: "", count: counts[""] }, ...["published", "draft", "archived"].filter((s) => counts[s]).map((s) => ({ label: s[0].toUpperCase() + s.slice(1), value: s, count: counts[s] }))]);
</script>

<PageHeader title="Pages" cli="cms pages{status ? ' --status ' + status : ''}">
  {#snippet actions()}{#if session.can("pages:write")}<Button variant="primary" icon="add" href="#/pages/new">Add New Page</Button>{/if}{/snippet}
</PageHeader>

<div class="flex flex-wrap items-center justify-between gap-3">
  <StatusLinks options={statusOptions} />
  {#if locales.length > 1}<QuickFilter title="Locale" param="locale" options={[{ label: "Any locale", value: "" }, ...locales.map((l) => ({ label: l, value: l }))]} />{/if}
</div>

<div class="flex flex-wrap items-center justify-between gap-2">
  {#if canBulk}
    <BulkActions noun="page" count={selected.length} onapply={bulk} actions={[
      ...(session.can("pages:delete") ? [{ value: "delete", label: "Move to trash", destructive: true, confirm: "They go to the trash with their child pages, where they can be restored." }] : []),
      ...(session.can("pages:publish") ? ["published", "draft", "archived"].map((s) => ({ value: "status-" + s, label: `Set to ${s}` })) : []),
    ]} />
  {:else}<span></span>{/if}
  <SearchBox placeholder="Search pages…" />
</div>

{#if list}
  <DataTable rows={list.pages} selectable={canBulk} bind:selected key="path"
    columns={[{ label: "Title" }, { label: "Path" }, { label: "Status" }, { label: "Locale" }, { label: "Updated" }]}
    emptyText={status || q || locale ? "No pages match." : "No pages yet. The first one is usually the home page."}>
    {#snippet row(p)}
      <Cell>
        <span class="inline-block" style="padding-left: {Math.min(q ? 0 : p.depth, 6) * 1.25}rem">
          {#if p.depth && !q}<span class="text-gray-400">↳ </span>{/if}
          <a href="#/pages/edit/{encodeURIComponent(p.path)}" class="font-medium text-gray-900 hover:underline">{p.title}</a>
        </span>
        <RowActions>
          {#if session.can("pages:write")}<RowAction href="#/pages/edit/{encodeURIComponent(p.path)}">Edit</RowAction>{/if}
          {#if site.siteURL && p.status === "published"}<RowAction href="{site.siteURL.replace(/\/$/, '')}/{p.path === 'home' ? '' : p.path}">View</RowAction>{/if}
          {#if session.can("pages:delete")}<RowAction danger onclick={() => trash(p)}>Trash</RowAction>{/if}
        </RowActions>
      </Cell>
      <Cell mono muted>/{p.path}</Cell>
      <Cell><Badge status={p.status} /></Cell>
      <Cell muted>{p.locale}</Cell>
      <Cell muted nowrap><Time value={p.updated_at} class="text-xs" /></Cell>
    {/snippet}
  </DataTable>
  <Pagination {page} per={list.per} total={list.total} />
{/if}
