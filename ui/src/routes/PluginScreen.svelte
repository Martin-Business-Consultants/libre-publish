<script>
  // A plugin's admin screen, described as data in its manifest: a table
  // filled from one of its routes. The admin draws it; the plugin ships no
  // code into the admin.
  import PageHeader from "../lib/components/PageHeader.svelte";
  import DataTable from "../lib/components/DataTable.svelte";
  import Cell from "../lib/components/Cell.svelte";
  import Spinner from "../lib/components/Spinner.svelte";
  import { get } from "../lib/api.js";
  import { toastError } from "../lib/toast.svelte.js";
  let { params } = $props();
  let screen = $state(null), rows = $state(null), raw = $state(null);
  (async () => {
    const p = (await get(`/plugins/${params.key}`)).plugin;
    screen = (p.admin?.screens || []).find((s) => s.id === params.screen);
    if (!screen) return;
    const data = await get(`/x/${params.key}${screen.source}`);
    if (screen.table) rows = (data[screen.table.rows] || []).map((r, i) => ({ ...r, __i: i })); else raw = data;
  })().catch(toastError);
</script>

{#if !screen}<div class="flex justify-center py-16"><Spinner /></div>{:else}
  <a href="#/plugins" class="text-sm text-gray-500 hover:text-gray-900">← Plugins</a>
  <PageHeader title={screen.title} icon="package" />
  {#if rows}
    <DataTable {rows} key="__i" columns={screen.table.columns.map((c) => ({ label: c.label }))} emptyText="Nothing yet.">
      {#snippet row(r)}{#each screen.table.columns as c}<Cell>{r[c.key] ?? ""}</Cell>{/each}{/snippet}
    </DataTable>
  {:else if raw}<pre class="overflow-auto rounded-lg border border-gray-200 bg-gray-50 p-4 font-mono text-xs">{JSON.stringify(raw, null, 2)}</pre>{/if}
{/if}
