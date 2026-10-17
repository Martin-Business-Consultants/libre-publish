<script>
  // Field definitions, edited as rows: label (the name follows it until
  // edited), type, required, and per type its options, collection, allowed
  // blocks or sub-fields (nested, for repeaters and groups). "Edit as JSON"
  // shows the same list as the API stores it.
  import SchemaEditor from "./SchemaEditor.svelte";
  import Button from "../components/Button.svelte";
  import DragHandle from "../components/DragHandle.svelte";
  import Input from "../components/Input.svelte";
  import Select from "../components/Select.svelte";
  import Switch from "../components/Switch.svelte";
  import TagInput from "../components/TagInput.svelte";
  import Combobox from "../components/Combobox.svelte";
  import Checkbox from "../components/Checkbox.svelte";
  import Textarea from "../components/Textarea.svelte";
  import { site } from "../site.svelte.js";
  import { blockTypes } from "../blocks.svelte.js";
  import { sortable, move } from "../sortable.js";

  let { fields, allowBlocks = true, depth = 1, errors = {}, path = "fields" } = $props();

  const TYPES = [
    ["richtext", "Rich text"], ["string", "Text (one line)"], ["text", "Plain text (paragraphs)"], ["markdown", "Markdown"], ["code", "Code"],
    ["integer", "Number"], ["boolean", "On/off"], ["select", "Choice"], ["url", "Address (URL)"], ["datetime", "Date and time"],
    ["link", "Link"], ["asset", "File or image"], ["record_ref", "Entry"], ["record_refs", "Entries"],
    ["string_list", "List of words"], ["group", "Group of fields"], ["repeater", "Repeating group"], ["blocks", "Blocks"],
  ];
  const typeOptions = $derived(TYPES.filter(([t]) => (allowBlocks || t !== "blocks") && (depth < 4 || !["group", "repeater"].includes(t))).map(([value, label]) => ({ value, label })));
  let mode = $state("rows");
  let json = $state("");
  let jsonError = $state("");
  let open = $state({});
  // svelte-ignore state_referenced_locally
  if (depth === 1) blockTypes.load();

  const nameOf = (label) => label.toLowerCase().normalize("NFKD").replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "").replace(/^(\d)/, "f_$1") || "";
  function add() {
    fields.push({ name: "", label: "", type: "string", __new: true });
    open[fields.length - 1] = true;
  }
  function setType(f, t) {
    f.type = t;
    if (t === "select" && !f.options) f.options = [];
    if ((t === "group" || t === "repeater") && !f.of) f.of = [];
    for (const k of ["options", "of_collection", "allowed_types", "of"]) {
      const keep = { options: ["select"], of_collection: ["record_ref", "record_refs"], allowed_types: ["blocks"], of: ["group", "repeater"] }[k];
      if (!keep.includes(t)) delete f[k];
    }
  }
  function toJSON() { json = JSON.stringify(clean($state.snapshot(fields)), null, 2); jsonError = ""; mode = "json"; }
  function fromJSON() {
    try {
      const v = JSON.parse(json);
      if (!Array.isArray(v)) throw new Error("It must be a list: [ … ].");
      fields.splice(0, fields.length, ...v);
      jsonError = ""; mode = "rows";
    } catch (e) { jsonError = e.message; }
  }
  function clean(list) { return list.map(({ __new, ...f }) => (f.of ? { ...f, of: clean(f.of) } : f)); }
  const errorAt = (i, key) => errors[`${path}[${i}].${key}`] || errors[`schema.${path}[${i}].${key}`];
</script>

<div class="flex flex-col gap-3">
  {#if depth === 1}
    <div class="flex items-center justify-between">
      <span class="text-xs font-medium text-muted-foreground">{fields.length} {fields.length === 1 ? "field" : "fields"}</span>
      {#if mode === "rows"}<Button variant="plain" size="sm" icon="code" onclick={toJSON}>Edit as JSON</Button>
      {:else}<Button variant="plain" size="sm" onclick={fromJSON}>Back to fields</Button>{/if}
    </div>
  {/if}

  {#if mode === "json"}
    <Textarea mono rows={16} bind:value={json} invalid={!!jsonError} spellcheck="false" />
    {#if jsonError}<p class="text-xs text-destructive">{jsonError}</p>{/if}
    <div><Button variant="primary" size="sm" onclick={fromJSON}>Apply JSON</Button></div>
  {:else}
    <div class="flex flex-col gap-3" {@attach sortable(() => fields)}>
    {#each fields as f, i (f)}
      <div class="bg-card rounded-lg border" data-sortable-item>
        <div class="flex flex-wrap items-center gap-2 p-2">
          <DragHandle onmove={(d) => move(fields, i, i + d)} />
          <div class="min-w-36 flex-1">
            <Input placeholder="Label" value={f.label || ""} aria-label="Label" invalid={!!errorAt(i, "name")}
              oninput={(e) => { f.label = e.currentTarget.value; if (f.__new || !f.name) f.name = nameOf(f.label); }} />
          </div>
          <div class="w-36"><Input mono placeholder="name" bind:value={f.name} oninput={() => delete f.__new} aria-label="Name" invalid={!!errorAt(i, "name")} /></div>
          <div class="w-48"><Select options={typeOptions} value={f.type} onchange={(v) => setType(f, v)} aria-label="Type" /></div>
          <Checkbox class="text-xs" label="Required" checked={!!f.required} onchange={(on) => (on ? (f.required = true) : delete f.required)} />
          <Button variant="plain" size="sm" iconOnly icon="sliders" title="More" onclick={() => (open[i] = !open[i])} aria-expanded={!!open[i]} />
          <Button variant="plain" size="sm" iconOnly icon="trash" title="Remove" class="hover:bg-destructive/10 hover:text-destructive" onclick={() => fields.splice(i, 1)} />
        </div>
        {#if errorAt(i, "name") || errorAt(i, "type") || errorAt(i, "options")}
          <p class="px-3 pb-2 text-xs text-destructive">{[errorAt(i, "name"), errorAt(i, "type"), errorAt(i, "options")].flat().filter(Boolean).join(", ")}</p>
        {/if}
        {#if open[i] || ["select", "group", "repeater"].includes(f.type)}
          <div class="flex flex-col gap-3 border-t border-border px-3 py-3 pl-9">
            {#if f.type === "select"}
              <div class="flex flex-col gap-1"><span class="text-xs font-medium text-muted-foreground">Choices</span><TagInput bind:value={f.options} placeholder="Add a choice and press Enter" /></div>
            {/if}
            {#if f.type === "record_ref" || f.type === "record_refs"}
              <div class="flex flex-col gap-1"><span class="text-xs font-medium text-muted-foreground">From the collection</span>
                <Select class="max-w-64" placeholder="—" options={site.collections.map((c) => ({ value: c.slug, label: c.name }))} bind:value={() => f.of_collection || "", (v) => (v ? (f.of_collection = v) : delete f.of_collection)} /></div>
            {/if}
            {#if f.type === "blocks"}
              <div class="flex flex-col gap-1"><span class="text-xs font-medium text-muted-foreground">Allowed blocks (none chosen: any)</span>
                <Combobox multiple placeholder="Any block" options={blockTypes.list.map((t) => ({ value: t.slug, label: t.label }))} bind:value={() => f.allowed_types || [], (v) => (v.length ? (f.allowed_types = v) : delete f.allowed_types)} /></div>
            {/if}
            {#if open[i]}
              <div class="flex flex-col gap-1"><span class="text-xs font-medium text-muted-foreground">Help</span>
                <Input placeholder="A line under the field, for whoever fills it in" bind:value={() => f.help || "", (v) => (v ? (f.help = v) : delete f.help)} /></div>
            {/if}
            {#if f.type === "group" || f.type === "repeater"}
              <div class="flex flex-col gap-1"><span class="text-xs font-medium text-muted-foreground">{f.type === "group" ? "Fields in the group" : "Fields in each item"}</span>
                <SchemaEditor fields={f.of} {allowBlocks} depth={depth + 1} {errors} path="{path}[{i}].of" /></div>
            {/if}
          </div>
        {/if}
      </div>
    {:else}
      <p class="rounded-lg bg-muted/50 py-6 text-center text-sm text-muted-foreground">No fields yet.</p>
    {/each}
    </div>
    <div><Button size="sm" icon="add" onclick={add}>Add field</Button></div>
  {/if}
</div>
