<script>
  // An asset field: the chosen file's preview and name, with Change and
  // Remove; choosing opens the media picker (upload, search, pick).
  import Button from "../components/Button.svelte";
  import Icon from "../components/Icon.svelte";
  import AssetPicker from "./AssetPicker.svelte";
  import { get } from "../api.js";
  let { value, onchange } = $props();
  let asset = $state(null), picking = $state(false);
  $effect(() => {
    const id = value;
    if (!id) { asset = null; return; }
    get(`/assets/${encodeURIComponent(id)}`).then((r) => (asset = r.asset)).catch(() => (asset = { id, filename: `Asset ${id} (missing)` }));
  });
</script>

{#if value}
  <div class="flex items-center gap-4 rounded-lg border border-gray-200 p-3">
    <div class="flex size-16 shrink-0 items-center justify-center overflow-hidden rounded-md bg-gray-100 text-gray-400">
      {#if asset?.thumb_url}<img src={asset.thumb_url} alt={asset.alt || ""} class="size-full object-cover" />{:else}<Icon name="document" size="lg" />{/if}
    </div>
    <div class="flex min-w-0 flex-col gap-2">
      <p class="truncate text-sm font-medium text-gray-900">{asset?.filename || "…"}</p>
      <div class="flex gap-2">
        <Button size="sm" onclick={() => (picking = true)}>Change</Button>
        <Button size="sm" variant="danger" onclick={() => onchange(null)}>Remove</Button>
      </div>
    </div>
  </div>
{:else}
  <button type="button" onclick={() => (picking = true)}
    class="flex items-center justify-center gap-2 rounded-lg border border-dashed border-gray-300 px-4 py-5 text-sm font-medium text-gray-600 hover:border-gray-400 hover:bg-gray-50 hover:text-gray-900">
    <Icon name="picture-add" size="md" /> Choose a file
  </button>
{/if}
<AssetPicker bind:open={picking} onpick={(a) => onchange(String(a.id))} />
