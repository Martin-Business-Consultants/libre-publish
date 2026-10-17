<script>
  import Field from "../components/Field.svelte";
  import Input from "../components/Input.svelte";
  import Textarea from "../components/Textarea.svelte";
  import Select from "../components/Select.svelte";
  import Switch from "../components/Switch.svelte";
  import TagInput from "../components/TagInput.svelte";
  import MarkdownEditor from "../components/MarkdownEditor.svelte";
  import LinkField from "./LinkField.svelte";
  import AssetField from "./AssetField.svelte";
  import RecordField from "./RecordField.svelte";
  import RepeaterField from "./RepeaterField.svelte";
  import FieldsForm from "./FieldsForm.svelte";
  import BlocksEditor from "./BlocksEditor.svelte";

  let { field: f, data, path, errors = {} } = $props();
  const label = $derived(f.label || f.name.replace(/_/g, " ").replace(/^./, (c) => c.toUpperCase()));
  const error = $derived(errors[path]);

  // The value, read and written through data[f.name]; blank means absent,
  // as the API reads it.
  function set(v) {
    if (v === "" || v == null || (Array.isArray(v) && !v.length && f.type !== "repeater" && f.type !== "blocks")) delete data[f.name];
    else data[f.name] = v;
  }
  // svelte-ignore state_referenced_locally
  if ((f.type === "group") && (typeof data[f.name] !== "object" || data[f.name] == null)) data[f.name] = {};
  // svelte-ignore state_referenced_locally
  if ((f.type === "repeater" || f.type === "blocks") && !Array.isArray(data[f.name])) data[f.name] = [];

  const toLocal = (iso) => {
    const d = new Date(iso);
    if (!iso || isNaN(d)) return "";
    const p = (n) => String(n).padStart(2, "0");
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`;
  };
</script>

{#if f.type === "boolean"}
  <div class="flex flex-col gap-1">
    <Switch checked={!!data[f.name]} onchange={(e) => (data[f.name] = e.currentTarget.checked)} {label} description={f.help} />
    {#if error}<p class="text-xs text-red-600">{error.join(", ")}</p>{/if}
  </div>
{:else if f.type === "group"}
  <fieldset class="rounded-lg border border-gray-200 px-4 pb-4 pt-2">
    <legend class="px-1 text-sm font-semibold text-gray-900">{label}{#if f.required}<span class="text-red-600"> *</span>{/if}</legend>
    {#if f.help}<p class="mb-3 text-xs text-gray-500">{f.help}</p>{/if}
    <FieldsForm fields={f.of || []} data={data[f.name]} {path} {errors} gap="gap-4" />
  </fieldset>
{:else if f.type === "repeater"}
  <Field {label} required={f.required} help={f.help} {error}>
    {#snippet children()}<RepeaterField field={f} items={data[f.name]} {path} {errors} />{/snippet}
  </Field>
{:else if f.type === "blocks"}
  <Field {label} required={f.required} help={f.help} {error}>
    {#snippet children()}<BlocksEditor blocks={data[f.name]} allowed={f.allowed_types} {path} {errors} />{/snippet}
  </Field>
{:else}
  <Field {label} required={f.required} help={f.help} {error}>
    {#snippet children(id, invalid)}
      {#if f.type === "text"}
        <Textarea {id} {invalid} rows={3} value={data[f.name] ?? ""} oninput={(e) => set(e.currentTarget.value)} />
      {:else if f.type === "markdown"}
        <MarkdownEditor {id} {invalid} bind:value={() => data[f.name] ?? "", (v) => set(v)} />
      {:else if f.type === "code"}
        <Textarea {id} {invalid} mono rows={6} value={data[f.name] ?? ""} oninput={(e) => set(e.currentTarget.value)} spellcheck="false" />
      {:else if f.type === "integer"}
        <Input {id} {invalid} type="number" step="1" class="max-w-48" value={data[f.name] ?? ""} oninput={(e) => set(e.currentTarget.value === "" ? null : parseInt(e.currentTarget.value, 10))} />
      {:else if f.type === "select"}
        <Select {id} {invalid} class="max-w-80" placeholder="—" options={f.options || []} value={data[f.name] ?? ""} onchange={(e) => set(e.currentTarget.value)} />
      {:else if f.type === "url"}
        <Input {id} {invalid} icon="link" placeholder="https://… or /path" value={data[f.name] ?? ""} oninput={(e) => set(e.currentTarget.value)} />
      {:else if f.type === "datetime"}
        <Input {id} {invalid} type="datetime-local" class="max-w-64" value={toLocal(data[f.name])} oninput={(e) => set(e.currentTarget.value ? new Date(e.currentTarget.value).toISOString() : null)} />
      {:else if f.type === "string_list"}
        <TagInput {id} {invalid} bind:value={() => data[f.name] ?? [], (v) => set(v)} />
      {:else if f.type === "link"}
        <LinkField value={data[f.name]} onchange={set} {invalid} />
      {:else if f.type === "asset"}
        <AssetField value={data[f.name]} onchange={set} />
      {:else if f.type === "record_ref" || f.type === "record_refs"}
        <RecordField {id} collection={f.of_collection} multiple={f.type === "record_refs"} value={data[f.name]} onchange={set} {invalid} />
      {:else}
        <Input {id} {invalid} value={data[f.name] ?? ""} oninput={(e) => set(e.currentTarget.value)} />
      {/if}
    {/snippet}
  </Field>
{/if}
