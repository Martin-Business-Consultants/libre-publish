<script>
  // An asset field: the chosen file's preview and name, with Change and
  // Remove; choosing opens the media picker (upload, search, pick).
  import Button from "../components/Button.svelte";
  import Icon from "../components/Icon.svelte";
  import AssetPicker from "./AssetPicker.svelte";
  import { get } from "../api.js";
  // accept: a type prefix the picker lists ("image").
  let { value, onchange, accept = "" } = $props();
  let asset = $state(null), picking = $state(false);
  $effect(() => {
    const id = value;
    if (!id) { asset = null; return; }
    get(`/assets/${encodeURIComponent(id)}`).then((r) => (asset = r.asset)).catch(() => (asset = { id, filename: `Asset ${id} (missing)` }));
  });
</script>

{#if value}
  <div class="flex items-center gap-4 rounded-lg border border-border p-3">
    <div class="flex size-16 shrink-0 items-center justify-center overflow-hidden rounded-md bg-muted text-muted-foreground">
      {#if asset?.thumb_url}<img src={asset.thumb_url} alt={asset.alt || ""} class="size-full object-cover" />{:else}<Icon name="document" size="lg" />{/if}
    </div>
    <div class="flex min-w-0 flex-col gap-2">
      <p class="truncate text-sm font-medium text-foreground">{asset?.filename || "…"}</p>
      <div class="flex gap-2">
        <Button size="sm" onclick={() => (picking = true)}>Change</Button>
        <Button size="sm" variant="danger" onclick={() => onchange(null)}>Remove</Button>
      </div>
    </div>
  </div>
{:else}
  <button type="button" onclick={() => (picking = true)}
    class="flex items-center justify-center gap-2 rounded-lg border border-dashed border-input px-4 py-5 text-sm font-medium text-muted-foreground hover:border-ring hover:bg-muted/50 hover:text-foreground">
    <Icon name="picture-add" size="md" /> Choose a file
  </button>
{/if}
<AssetPicker bind:open={picking} {accept} onpick={(a) => onchange(String(a.id))} />
