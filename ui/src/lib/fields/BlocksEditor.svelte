<script>
  // The block editor (content-form.css .content-row): each block a row
  // showing its type, its category and a line of what it says, folded until
  // opened; drag it by its handle to reorder; insert one after it,
  // duplicate it, remove it. Errors from the API open and mark the block
  // they're in.
  import FieldsForm from "./FieldsForm.svelte";
  import BlockPicker from "./BlockPicker.svelte";
  import Button from "../components/Button.svelte";
  import Badge from "../components/Badge.svelte";
  import Icon from "../components/Icon.svelte";
  import DragHandle from "../components/DragHandle.svelte";
  import { sortable, move } from "../sortable.js";
  import { blockTypes } from "../blocks.svelte.js";
  let { blocks, allowed = null, path = "blocks", errors = {} } = $props();
  let picking = $state(false);
  let insertAt = $state(null);
  let open = $state(new Set());
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

<div class="flex flex-col gap-2" {@attach sortable(() => blocks)}>
  {#if blocks.length > 1}
    <div class="-mt-1 flex justify-end"><button type="button" class="text-xs font-medium text-muted-foreground hover:text-foreground" onclick={() => (open = allOpen ? new Set() : new Set(blocks))}>{allOpen ? "Collapse all" : "Expand all"}</button></div>
  {/if}
  {#each blocks as b, i (b)}
    {@const t = blockTypes.find(b.type)}
    {@const bad = errorsIn(i)}
    {@const isOpen = open.has(b)}
    <div class="bg-card rounded-lg border {bad.length ? 'border-destructive/50' : ''}" data-sortable-item>
      <div class="flex items-center gap-2 py-1.5 pl-1.5 pr-1.5 {isOpen ? 'border-b border-border' : ''}">
        <DragHandle onmove={(d) => move(blocks, i, i + d)} />
        <button type="button" class="flex min-w-0 flex-1 items-center gap-2 text-left" onclick={() => toggle(b)} aria-expanded={isOpen}>
          <Icon name="caret-down" class="text-muted-foreground transition-transform {isOpen ? '' : '-rotate-90'}" />
          <span class="flex min-w-0 flex-col">
            <span class="flex items-center gap-2">
              <span class="truncate text-sm font-medium text-foreground">{t?.label || b.type}</span>
              {#if t?.category}<span class="hidden sm:inline"><Badge>{t.category}</Badge></span>{/if}
              {#if bad.length}<Badge tone="danger">Needs attention</Badge>{/if}
            </span>
            {#if summary(b)}<span class="truncate text-xs text-muted-foreground">{summary(b)}</span>{/if}
          </span>
        </button>
        <div class="flex shrink-0 items-center">
          <span class="hidden sm:flex">
            <Button variant="plain" size="sm" iconOnly icon="add" title="Add a block after this one" onclick={() => { insertAt = i; picking = true; }} />
            <Button variant="plain" size="sm" iconOnly icon="copy-paste" title="Duplicate" onclick={() => duplicate(i)} />
          </span>
          <Button variant="plain" size="sm" iconOnly icon="trash" title="Remove" class="hover:bg-destructive/10 hover:text-destructive" onclick={() => blocks.splice(i, 1)} />
        </div>
      </div>
      {#if isOpen}
        <div class="p-4">
          {#if t}
            <FieldsForm fields={t.fields} data={b.data} path="{path}[{i}].data" {errors} gap="gap-4" />
          {:else}
            {#if blockTypes.loaded}<p class="text-sm text-muted-foreground">There's no block type “{b.type}” any more; its content is kept as it is.</p>{/if}
          {/if}
        </div>
      {/if}
    </div>
  {:else}
    <div class="rounded-lg bg-muted/50 py-8 text-center text-sm text-muted-foreground">No blocks yet.</div>
  {/each}
  <div><Button icon="add" onclick={() => { insertAt = null; picking = true; }}>Add block</Button></div>
</div>
<BlockPicker bind:open={picking} {allowed} onpick={add} />
