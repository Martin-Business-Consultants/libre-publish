<script>
  // The block editor (content-form.css .content-row): each block a folding
  // row with its type, a summary, and moves (up, down, duplicate, remove),
  // its form inside; "Add block" opens the picker. Errors from the API open
  // and mark the block they're in.
  import FieldsForm from "./FieldsForm.svelte";
  import BlockPicker from "./BlockPicker.svelte";
  import Button from "../components/Button.svelte";
  import Icon from "../components/Icon.svelte";
  import { blockTypes } from "../blocks.svelte.js";
  let { blocks, allowed = null, path = "blocks", errors = {} } = $props();
  let picking = $state(false);
  let collapsed = $state({});
  blockTypes.load();
  // svelte-ignore state_referenced_locally
  for (const b of blocks) if (!b.data || typeof b.data !== "object") b.data = {};

  const summary = (b) => {
    const d = b.data || {};
    const s = d.heading || d.title || d.label || d.text || d.eyebrow || d.body || d.collection_slug || "";
    return typeof s === "string" ? s.replace(/[#*_`>]/g, "").slice(0, 90) : "";
  };
  const errorsIn = (i) => Object.keys(errors).filter((k) => k.startsWith(`${path}[${i}]`));
  function move(i, d) { const [x] = blocks.splice(i, 1); blocks.splice(i + d, 0, x); }
  function duplicate(i) { const copy = JSON.parse(JSON.stringify($state.snapshot(blocks[i]))); delete copy.id; blocks.splice(i + 1, 0, copy); }
  function add(t) { blocks.push({ type: t.slug, version: t.version, data: JSON.parse(JSON.stringify(t.defaults || {})) }); }
  const key = (b) => b.id || b;
</script>

<div class="flex flex-col gap-2">
  {#each blocks as b, i (key(b))}
    {@const t = blockTypes.find(b.type)}
    {@const bad = errorsIn(i)}
    {@const k = b.id || i}
    <div class="rounded-lg border bg-surface {bad.length ? 'border-red-300' : 'border-gray-200'}">
      <div class="flex items-center gap-2 py-1.5 pl-2 pr-1.5 {collapsed[k] ? '' : 'border-b border-gray-200'}">
        <button type="button" class="flex min-w-0 flex-1 items-center gap-2 text-left" onclick={() => (collapsed[k] = !collapsed[k])} aria-expanded={!collapsed[k]}>
          <Icon name="caret-down" class="text-gray-400 transition-transform {collapsed[k] ? '-rotate-90' : ''}" />
          <span class="flex min-w-0 flex-col">
            <span class="truncate text-sm font-medium text-gray-900">{t?.label || b.type}{#if bad.length}<span class="ml-2 text-xs font-normal text-red-600">needs attention</span>{/if}</span>
            {#if summary(b)}<span class="truncate text-xs text-gray-500">{summary(b)}</span>{/if}
          </span>
        </button>
        <span class="hidden text-xs text-gray-400 sm:inline">{t?.category || ""}</span>
        <div class="flex shrink-0 items-center">
          <Button variant="plain" size="sm" iconOnly icon="arrow-up" title="Move up" disabled={i === 0} onclick={() => move(i, -1)} />
          <Button variant="plain" size="sm" iconOnly icon="arrow-up" class="rotate-180" title="Move down" disabled={i === blocks.length - 1} onclick={() => move(i, 1)} />
          <span class="hidden sm:flex"><Button variant="plain" size="sm" iconOnly icon="copy-paste" title="Duplicate" onclick={() => duplicate(i)} /></span>
          <Button variant="plain" size="sm" iconOnly icon="trash" title="Remove" class="hover:!bg-red-50 hover:!text-red-700" onclick={() => blocks.splice(i, 1)} />
        </div>
      </div>
      {#if !collapsed[k]}
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
  <div><Button icon="add" onclick={() => (picking = true)}>Add block</Button></div>
</div>
<BlockPicker bind:open={picking} {allowed} onpick={add} />
