<script>
  // A reference to entries of a collection, by slug, as the API stores them.
  import Combobox from "../components/Combobox.svelte";
  import Input from "../components/Input.svelte";
  import { get } from "../api.js";
  let { collection, multiple = false, value, onchange, invalid = false, id = undefined } = $props();
  let options = $state([]);
  let loaded = $state(false);
  $effect(() => {
    if (!collection) return;
    get(`/collections/${encodeURIComponent(collection)}/entries?per=100`)
      .then((r) => { options = r.entries.map((e) => ({ value: e.slug, label: e.title, hint: e.status !== "published" ? e.status : e.slug })); loaded = true; })
      .catch(() => (loaded = true));
  });
</script>

{#if collection}
  <Combobox {id} {multiple} {invalid} {options} placeholder={loaded ? `Choose from ${collection}…` : "Loading…"}
    value={multiple ? (Array.isArray(value) ? value : []) : value ?? null} onchange={onchange} />
{:else}
  <Input {id} {invalid} placeholder={multiple ? "entry slugs, comma-separated" : "entry slug"}
    value={multiple ? (value || []).join(", ") : value ?? ""}
    oninput={(e) => onchange(multiple ? e.currentTarget.value.split(",").map((s) => s.trim()).filter(Boolean) : e.currentTarget.value)} />
{/if}
