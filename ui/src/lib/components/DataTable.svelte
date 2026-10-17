<script>
  // A list table (tables.css .data-table) in a panel: headers, rows that
  // light up under the pointer, a tick column with select-all when rows can
  // be acted on in bulk, and an empty row that says why it's empty.
  //   <DataTable {columns} rows={pages} key="id" selectable bind:selected>
  //     {#snippet row(page)}<td>…</td>{/snippet}
  //   </DataTable>
  let {
    columns = [],
    rows = [],
    key = "id",
    selectable = false,
    selected = $bindable([]),
    row,
    empty = undefined,
    emptyText = "Nothing here yet.",
    onrowclick = undefined,
    class: klass = "",
  } = $props();

  const ids = $derived(rows.map((r) => r[key]));
  const all = $derived(ids.length > 0 && ids.every((id) => selected.includes(id)));
  const some = $derived(!all && ids.some((id) => selected.includes(id)));
  function toggleAll() { selected = all ? [] : [...ids]; }
  function toggle(id) { selected = selected.includes(id) ? selected.filter((x) => x !== id) : [...selected, id]; }
  const span = $derived(columns.length + (selectable ? 1 : 0));
</script>

<section class="min-w-0 overflow-x-auto rounded-xl border border-gray-200 bg-surface {klass}">
  <table class="w-full text-left text-sm leading-5">
    <thead>
      <tr>
        {#if selectable}
          <th class="w-10 border-b border-gray-200 px-3 py-2">
            {#if rows.length}<input type="checkbox" checked={all} indeterminate={some} onchange={toggleAll} aria-label="Select every row" />{/if}
          </th>
        {/if}
        {#each columns as c}
          <th class="whitespace-nowrap border-b border-gray-200 px-3 py-2 text-xs font-medium leading-4 text-gray-500 {c.num ? 'text-right' : ''} {c.class || ''}">{c.label}</th>
        {/each}
      </tr>
    </thead>
    <tbody>
      {#each rows as r (r[key])}
        <tr
          class="group border-b border-gray-100 last:border-0 hover:bg-gray-50 {onrowclick ? 'cursor-pointer' : ''} {selected.includes(r[key]) ? 'bg-accent-50/40' : ''}"
          onclick={onrowclick ? (e) => { if (!e.target.closest('a,button,input,label')) onrowclick(r); } : undefined}
        >
          {#if selectable}
            <td class="w-10 px-3 py-2.5"><input type="checkbox" checked={selected.includes(r[key])} onchange={() => toggle(r[key])} aria-label="Select" /></td>
          {/if}
          {@render row(r)}
        </tr>
      {:else}
        <tr>
          <td colspan={span} class="px-3 py-12 text-center text-gray-500">
            {#if empty}{@render empty()}{:else}{emptyText}{/if}
          </td>
        </tr>
      {/each}
    </tbody>
  </table>
</section>
