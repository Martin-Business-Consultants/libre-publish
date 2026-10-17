<script>
  // A link: {kind: url|page|entry, value, collection?, label?}. A page is
  // chosen from the pages; an entry from its collection.
  import Select from "../components/Select.svelte";
  import Input from "../components/Input.svelte";
  import Combobox from "../components/Combobox.svelte";
  import { get } from "../api.js";
  import { site } from "../site.svelte.js";
  let { value, onchange, invalid = false } = $props();
  // svelte-ignore state_referenced_locally
  let v = $state(
    value && typeof value === "object"
      ? { kind: value.kind || "url", value: value.value ?? "", collection: value.collection ?? "", label: value.label ?? "" }
      : { kind: "url", value: typeof value === "string" ? value : "", collection: "", label: "" },
  );
  let pages = $state([]), entries = $state([]);
  $effect(() => { if (v.kind === "page" && !pages.length) get("/pages?per=100").then((r) => (pages = r.pages)).catch(() => {}); });
  $effect(() => {
    if (v.kind === "entry" && v.collection) get(`/collections/${encodeURIComponent(v.collection)}/entries?per=100`).then((r) => (entries = r.entries)).catch(() => (entries = []));
  });
  function emit() {
    const out = { kind: v.kind, value: v.value };
    if (v.kind === "entry" && v.collection) out.collection = v.collection;
    if (v.label) out.label = v.label;
    onchange(v.value ? out : null);
  }
</script>

<div class="flex flex-wrap items-start gap-2">
  <Select class="w-28" options={[{ value: "url", label: "Address" }, { value: "page", label: "Page" }, { value: "entry", label: "Entry" }]}
    bind:value={v.kind} onchange={() => { v.value = ""; emit(); }} aria-label="Link to" />
  {#if v.kind === "url"}
    <div class="min-w-48 flex-1"><Input icon="link" {invalid} placeholder="https://… or /path" bind:value={v.value} oninput={emit} aria-label="Address" /></div>
  {:else if v.kind === "page"}
    <div class="min-w-48 flex-1"><Combobox {invalid} placeholder="Choose a page…" options={pages.map((p) => ({ value: p.path, label: p.title, hint: "/" + p.path }))} bind:value={v.value} onchange={emit} /></div>
  {:else}
    <Select class="w-40" placeholder="Collection" options={site.collections.map((c) => ({ value: c.slug, label: c.name }))} bind:value={v.collection} onchange={() => { v.value = ""; emit(); }} aria-label="Collection" />
    <div class="min-w-48 flex-1"><Combobox {invalid} placeholder="Choose an entry…" options={entries.map((e) => ({ value: e.slug, label: e.title, hint: e.slug }))} bind:value={v.value} onchange={emit} /></div>
  {/if}
  <div class="w-40"><Input placeholder="Label (optional)" bind:value={v.label} oninput={emit} aria-label="Label" /></div>
</div>
