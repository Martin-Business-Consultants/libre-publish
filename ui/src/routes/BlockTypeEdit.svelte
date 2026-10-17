<script>
  // A block type: its fields (the schema editor), what a new block starts
  // with, and how the picker shows it.
  import PageHeader from "../lib/components/PageHeader.svelte";
  import Panel from "../lib/components/Panel.svelte";
  import Postbox from "../lib/components/Postbox.svelte";
  import Field from "../lib/components/Field.svelte";
  import Input from "../lib/components/Input.svelte";
  import Textarea from "../lib/components/Textarea.svelte";
  import Switch from "../lib/components/Switch.svelte";
  import Button from "../lib/components/Button.svelte";
  import Spinner from "../lib/components/Spinner.svelte";
  import SchemaEditor from "../lib/fields/SchemaEditor.svelte";
  import FieldsForm from "../lib/fields/FieldsForm.svelte";
  import { get, post, patch } from "../lib/api.js";
  import { save, saveShortcut } from "../lib/save.js";
  import { blockTypes } from "../lib/blocks.svelte.js";
  import { slugify } from "../lib/format.js";
  import { go } from "../lib/router.svelte.js";
  import { toastError } from "../lib/toast.svelte.js";
  import { onDestroy } from "svelte";

  let { params } = $props();
  // svelte-ignore state_referenced_locally
  const slug = params.slug === "new" ? null : params.slug;
  let t = $state(null), errors = $state({}), saving = $state(false), preview = $state({});
  async function load() {
    t = slug ? (await get(`/block_types/${slug}`)).block_type : { label: "", slug: "", category: "", description: "", deprecated: false, fields: [], defaults: {} };
    preview = JSON.parse(JSON.stringify(t.defaults || {}));
  }
  load().catch(toastError);
  async function submit() {
    saving = true;
    const body = { block_type: { label: t.label, slug: t.slug, category: t.category, description: t.description, deprecated: t.deprecated,
      fields: $state.snapshot(t.fields).map(({ __new, ...f }) => f), defaults: $state.snapshot(preview) } };
    const r = await save(() => (slug ? patch(`/block_types/${slug}`, body) : post("/block_types", body)));
    saving = false; errors = r.errors || {};
    if (r.ok) { await blockTypes.load(true); if (r.res.block_type.slug !== slug) go(`/blocks/${r.res.block_type.slug}`); else load(); }
  }
  const stop = saveShortcut(submit);
  onDestroy(stop);
</script>

{#if !t}
  <div class="flex justify-center py-16"><Spinner /></div>
{:else}
  <PageHeader title={slug ? t.label : "New block type"} icon="grid">
    {#snippet actions()}<Button href="#/blocks">All block types</Button><Button variant="primary" loading={saving} onclick={submit}>{slug ? "Save changes" : "Create block type"}</Button>{/snippet}
  </PageHeader>
  <div class="flex flex-col gap-6 lg:flex-row lg:items-start">
    <div class="flex min-w-0 flex-1 flex-col gap-6">
      <Panel title="Fields"><div class="p-5"><SchemaEditor fields={t.fields} {errors} path="fields" /></div></Panel>
      <Panel title="A new block starts with">
        <div class="p-5">
          {#if t.fields.length}
            <p class="mb-4 text-sm text-gray-500">Fill in what a new {t.label || "block"} should already say. This is also how the form looks to an editor.</p>
            {#key JSON.stringify(t.fields.map((f) => [f.name, f.type]))}<FieldsForm fields={t.fields} data={preview} path="defaults" {errors} />{/key}
          {:else}<p class="text-sm text-gray-500">Add fields first.</p>{/if}
        </div>
      </Panel>
    </div>
    <aside class="flex min-w-0 shrink-0 flex-col gap-4 lg:sticky lg:top-16 lg:w-80">
      <Postbox key="block-type" title="Block type">
        <Field label="Label" required error={errors.label}>{#snippet children(id, invalid)}<Input {id} {invalid} bind:value={t.label} oninput={() => { if (!slug) t.slug = slugify(t.label).replace(/-/g, "_"); }} />{/snippet}</Field>
        <Field label="Slug" help="What blocks are stored and rendered by." error={errors.slug}>{#snippet children(id, invalid)}<Input {id} {invalid} mono bind:value={t.slug} disabled={!!slug && t.built_in} />{/snippet}</Field>
        <Field label="Category" help="Groups it in the block picker.">{#snippet children(id)}<Input {id} bind:value={t.category} placeholder="Sections" />{/snippet}</Field>
        <Field label="Description">{#snippet children(id)}<Textarea {id} rows={2} bind:value={t.description} />{/snippet}</Field>
        <Switch bind:checked={t.deprecated} label="Deprecated" description="Hidden from the picker; existing blocks keep working." />
      </Postbox>
    </aside>
  </div>
{/if}
