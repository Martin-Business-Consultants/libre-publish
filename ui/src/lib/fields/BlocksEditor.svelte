<script>
  // The block editor (content-form.css .content-row): each block a row
  // showing its type, its category and a line of what it says, folded until
  // opened; drag it by its handle, or move it up and down; insert one after
  // it, duplicate it, remove it. Errors from the API open and mark the block
  // they're in.
  import FieldsForm from "./FieldsForm.svelte";
  import BlockPicker from "./BlockPicker.svelte";
  import Button from "../components/Button.svelte";
  import Badge from "../components/Badge.svelte";
  import Icon from "../components/Icon.svelte";
  import { blockTypes } from "../blocks.svelte.js";
  let { blocks, allowed = null, path = "blocks", errors = {} } = $props();
  let picking = $state(false);
  let insertAt = $state(null);
  let open = $state(new Set());
  let dragFrom = $state(null), dragOver = $state(null);
  blockTypes.load();
  // svelte-ignore state_referenced_locally
  for (const b of blocks) if (!b.data || typeof b.data !== "object") b.data = {};

  const summary = (b) => {
    const d = b.data || {};
    const s = d.heading || d.title || d.label || d.eyebrow || d.text || d.body || d.quote_form_title || d.collection_slug || "";
    return typeof s === "string" ? s.replace(/[#*_`>]/g, "").slice(0, 100) : "";
  };
  const errorsIn = (i) => Object.keys(errors).filter((k) => k.startsWith(`${path}[${i}]`));
  $effect(() => {
    // A block the API complained about opens.
    const bad = blocks.map((b, i) => (errorsIn(i).length ? b : null)).filter(Boolean);
    if (bad.length) open = new Set([...open, ...bad]);
  });
  function toggle(b) { const n = new Set(open); n.has(b) ? n.delete(b) : n.add(b); open = n; }
  function move(from, to) { if (to < 0 || to >= blocks.length || from === to) return; const [x] = blocks.splice(from, 1); blocks.splice(to, 0, x); }
  function duplicate(i) { const copy = JSON.parse(JSON.stringify($state.snapshot(blocks[i]))); delete copy.id; blocks.splice(i + 1, 0, copy); }
  function add(t) {
    const b = { type: t.slug, version: t.version, data: JSON.parse(JSON.stringify(t.defaults || {})) };
    const at = insertAt == null ? blocks.length : insertAt + 1;
    blocks.splice(at, 0, b);
    open = new Set([...open, blocks[at]]);
    insertAt = null;
  }
  const allOpen = $derived(blocks.length > 0 && blocks.every((b) => open.has(b)));
</script>

<div class="flex flex-col gap-2">
  {#if blocks.length > 1}
    <div class="-mt-1 flex justify-end"><button type="button" class="text-xs font-medium text-gray-500 hover:text-gray-900" onclick={() => (open = allOpen ? new Set() : new Set(blocks))}>{allOpen ? "Collapse all" : "Expand all"}</button></div>
  {/if}
  {#each blocks as b, i (b)}
    {@const t = blockTypes.find(b.type)}
    {@const bad = errorsIn(i)}
    {@const isOpen = open.has(b)}
    <div
      class="rounded-lg border bg-surface transition-shadow {bad.length ? 'border-red-300' : 'border-gray-200'} {dragFrom === i ? 'opacity-50' : ''} {dragOver === i && dragFrom !== i ? 'shadow-[0_-2px_0_0_var(--accent-500)]' : ''}"
      role="listitem"
      ondragover={(e) => { if (dragFrom !== null) { e.preventDefault(); dragOver = i; } }}
      ondrop={(e) => { e.preventDefault(); if (dragFrom !== null) move(dragFrom, i); dragFrom = dragOver = null; }}
    >
      <div class="flex items-center gap-2 py-1.5 pl-1.5 pr-1.5 {isOpen ? 'border-b border-gray-200' : ''}">
        <span class="cursor-grab px-1 text-gray-400 hover:text-gray-700 active:cursor-grabbing" draggable="true" role="button" tabindex="-1" aria-label="Drag to reorder"
          ondragstart={(e) => { dragFrom = i; e.dataTransfer.effectAllowed = "move"; }} ondragend={() => (dragFrom = dragOver = null)}>⠿</span>
        <button type="button" class="flex min-w-0 flex-1 items-center gap-2 text-left" onclick={() => toggle(b)} aria-expanded={isOpen}>
          <Icon name="caret-down" class="text-gray-400 transition-transform {isOpen ? '' : '-rotate-90'}" />
          <span class="flex min-w-0 flex-col">
            <span class="flex items-center gap-2">
              <span class="truncate text-sm font-medium text-gray-900">{t?.label || b.type}</span>
              {#if t?.category}<span class="hidden sm:inline"><Badge>{t.category}</Badge></span>{/if}
              {#if bad.length}<Badge tone="danger">Needs attention</Badge>{/if}
            </span>
            {#if summary(b)}<span class="truncate text-xs text-gray-500">{summary(b)}</span>{/if}
          </span>
        </button>
        <div class="flex shrink-0 items-center">
          <Button variant="plain" size="sm" iconOnly icon="arrow-up" title="Move up" disabled={i === 0} onclick={() => move(i, i - 1)} />
          <Button variant="plain" size="sm" iconOnly icon="arrow-up" class="rotate-180" title="Move down" disabled={i === blocks.length - 1} onclick={() => move(i, i + 1)} />
          <span class="hidden sm:flex">
            <Button variant="plain" size="sm" iconOnly icon="add" title="Add a block after this one" onclick={() => { insertAt = i; picking = true; }} />
            <Button variant="plain" size="sm" iconOnly icon="copy-paste" title="Duplicate" onclick={() => duplicate(i)} />
          </span>
          <Button variant="plain" size="sm" iconOnly icon="trash" title="Remove" class="hover:!bg-red-50 hover:!text-red-700" onclick={() => blocks.splice(i, 1)} />
        </div>
      </div>
      {#if isOpen}
        <div class="p-4">
          {#if t}
            <FieldsForm fields={t.fields} data={b.data} path="{path}[{i}].data" {errors} gap="gap-4" />
          {:else}
            <p class="text-sm text-gray-500">There's no block type “{b.type}” any more; its content is kept as it is.</p>
          {/if}
        </div>
      {/if}
    </div>
  {:else}
    <div class="rounded-lg bg-gray-50 py-8 text-center text-sm text-gray-500">No blocks yet.</div>
  {/each}
  <div><Button icon="add" onclick={() => { insertAt = null; picking = true; }}>Add block</Button></div>
</div>
<BlockPicker bind:open={picking} {allowed} onpick={add} />
