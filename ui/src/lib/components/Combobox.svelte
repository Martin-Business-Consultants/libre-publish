<script>
  // A searchable select: type to narrow, arrows and Enter to choose, Escape
  // to close. `multiple` keeps several, drawn as removable chips before the
  // search (Backspace on an empty search removes the last).
  //   options: [{ value, label, hint? }]
  import Icon from "./Icon.svelte";
  let {
    value = $bindable(null),
    options = [],
    multiple = false,
    placeholder = "Choose…",
    emptyText = "Nothing matches.",
    invalid = false,
    clearable = true,
    id = undefined,
    onchange = undefined,
  } = $props();

  const uid = $props.id();
  let open = $state(false);
  let query = $state("");
  let active = $state(0);
  let root = $state();
  let input = $state();

  const chosen = $derived(multiple ? (Array.isArray(value) ? value : []) : value == null || value === "" ? [] : [value]);
  const labelOf = (v) => options.find((o) => String(o.value) === String(v))?.label ?? String(v);
  const filtered = $derived.by(() => {
    const q = query.trim().toLowerCase();
    return options.filter((o) => !q || o.label.toLowerCase().includes(q) || String(o.value).toLowerCase().includes(q) || (o.hint || "").toLowerCase().includes(q));
  });
  $effect(() => { if (active >= filtered.length) active = Math.max(0, filtered.length - 1); });

  function pick(o) {
    if (multiple) {
      value = chosen.some((v) => String(v) === String(o.value)) ? chosen.filter((v) => String(v) !== String(o.value)) : [...chosen, o.value];
      query = "";
      input?.focus();
    } else {
      value = o.value;
      open = false;
      query = "";
    }
    onchange?.(value);
  }
  function remove(v) {
    value = multiple ? chosen.filter((x) => String(x) !== String(v)) : null;
    onchange?.(value);
  }
  function key(e) {
    if (e.key === "ArrowDown") { e.preventDefault(); open = true; active = Math.min(active + 1, filtered.length - 1); scroll(); }
    else if (e.key === "ArrowUp") { e.preventDefault(); active = Math.max(active - 1, 0); scroll(); }
    else if (e.key === "Enter") { if (open && filtered[active]) { e.preventDefault(); pick(filtered[active]); } }
    else if (e.key === "Escape") { if (open) { e.stopPropagation(); open = false; } }
    else if (e.key === "Backspace" && multiple && !query && chosen.length) remove(chosen[chosen.length - 1]);
  }
  function scroll() {
    queueMicrotask(() => root?.querySelector(`[data-index="${active}"]`)?.scrollIntoView({ block: "nearest" }));
  }
  function outside(e) { if (open && root && !root.contains(e.target)) { open = false; query = ""; } }
</script>

<svelte:document onclick={outside} />
<div class="relative" bind:this={root}>
  <div
    class="flex min-h-8 w-full cursor-text flex-wrap items-center gap-1 rounded-md border bg-surface py-0.5 pl-1.5 pr-8 text-sm leading-5 {invalid ? 'border-red-500' : open ? 'border-gray-900' : 'border-gray-300 hover:border-gray-400'}"
    onclick={() => { open = true; input?.focus(); }}
    role="presentation"
  >
    {#if multiple}
      {#each chosen as v (v)}
        <span class="inline-flex items-center gap-1 rounded-sm bg-gray-100 py-0.5 pl-1.5 pr-0.5 text-xs font-medium text-gray-800">
          {labelOf(v)}
          <button type="button" class="rounded-sm p-0.5 text-gray-500 hover:bg-gray-200 hover:text-gray-900" onclick={(e) => { e.stopPropagation(); remove(v); }} aria-label="Remove {labelOf(v)}"><Icon name="close" size="xs" /></button>
        </span>
      {/each}
    {/if}
    <input
      bind:this={input}
      {id}
      bind:value={query}
      onfocus={() => (open = true)}
      oninput={() => { open = true; active = 0; }}
      onkeydown={key}
      class="min-w-16 flex-1 border-0 bg-transparent px-1 py-1 text-gray-900 outline-none placeholder:text-gray-400"
      placeholder={chosen.length && !multiple ? labelOf(chosen[0]) : chosen.length ? "" : placeholder}
      role="combobox"
      aria-expanded={open}
      aria-controls="cb-{uid}"
      aria-autocomplete="list"
      autocomplete="off"
    />
    {#if !multiple && chosen.length && !query}
      <span class="pointer-events-none absolute left-2.5 right-8 truncate text-gray-900 {open ? 'opacity-0' : ''}">{labelOf(chosen[0])}</span>
    {/if}
    <span class="absolute right-2 flex items-center gap-1 text-gray-400">
      {#if clearable && !multiple && chosen.length}
        <button type="button" class="rounded-sm p-0.5 hover:bg-gray-100 hover:text-gray-900" onclick={(e) => { e.stopPropagation(); remove(chosen[0]); }} aria-label="Clear"><Icon name="close" size="xs" /></button>
      {:else}
        <Icon name="caret-down" size="xs" />
      {/if}
    </span>
  </div>
  {#if open}
    <ul id="cb-{uid}" class="absolute inset-x-0 top-[calc(100%+0.25rem)] z-30 max-h-72 animate-pop-in overflow-y-auto rounded-xl border border-gray-200 bg-surface p-1 shadow-overlay" role="listbox" aria-multiselectable={multiple}>
      {#each filtered as o, i (o.value)}
        {@const on = chosen.some((v) => String(v) === String(o.value))}
        <li role="option" aria-selected={on} data-index={i}>
          <button type="button" tabindex="-1" onmousemove={() => (active = i)} onclick={(e) => { e.stopPropagation(); pick(o); }}
            class="flex w-full items-center justify-between gap-2 rounded-md px-2.5 py-1.5 text-left text-sm {i === active ? 'bg-gray-100 text-gray-900' : 'text-gray-700'}">
            <span class="min-w-0 flex-1">
              <span class="block truncate {on ? 'font-medium' : ''}">{o.label}</span>
              {#if o.hint}<span class="block truncate text-xs text-gray-500">{o.hint}</span>{/if}
            </span>
            {#if on}<Icon name="check" class="text-accent-600" />{/if}
          </button>
        </li>
      {:else}
        <li class="px-2.5 py-1.5 text-sm text-gray-500">{emptyText}</li>
      {/each}
    </ul>
  {/if}
</div>
