<script>
  // A collection: its entries' fields (the schema editor), and its settings.
  import PageHeader from "../lib/components/PageHeader.svelte";
  import Panel from "../lib/components/Panel.svelte";
  import Postbox from "../lib/components/Postbox.svelte";
  import Field from "../lib/components/Field.svelte";
  import Input from "../lib/components/Input.svelte";
  import Select from "../lib/components/Select.svelte";
  import Switch from "../lib/components/Switch.svelte";
  import Button from "../lib/components/Button.svelte";
  import Spinner from "../lib/components/Spinner.svelte";
  import SchemaEditor from "../lib/fields/SchemaEditor.svelte";
  import { get, post, patch, del } from "../lib/api.js";
  import { save, saveShortcut } from "../lib/save.js";
  import { session } from "../lib/session.svelte.js";
  import { site } from "../lib/site.svelte.js";
  import { confirm } from "../lib/confirm.svelte.js";
  import { toast, toastError } from "../lib/toast.svelte.js";
  import { go } from "../lib/router.svelte.js";
  import { slugify } from "../lib/format.js";
  import { onDestroy } from "svelte";

  let { params } = $props();
  // svelte-ignore state_referenced_locally
  const slug = params.slug || null;
  let c = $state(null), fields = $state([]), errors = $state({}), saving = $state(false);
  async function load() {
    if (slug) { const r = (await get(`/collections/${slug}`)).collection; c = r; fields = r.schema?.fields || []; }
    else c = { name: "", slug: "", enable_blocks: false, api_enabled: false, categories_collection_id: null, tags_collection_id: null };
  }
  load().catch(toastError);
  async function submit() {
    saving = true;
    const body = { collection: { name: c.name, slug: c.slug, enable_blocks: c.enable_blocks, api_enabled: c.api_enabled,
      categories_collection_id: c.categories_collection_id || null, tags_collection_id: c.tags_collection_id || null,
      schema: { fields: $state.snapshot(fields).map(({ __new, ...f }) => f) } } };
    const r = await save(() => (slug ? patch(`/collections/${slug}`, body) : post("/collections", body)));
    saving = false; errors = r.errors || {};
    if (r.ok) { await site.refresh(); if (r.res.collection.slug !== slug) go(`/collections/${r.res.collection.slug}/settings`); else load(); }
  }
  async function remove() {
    if (!(await confirm({ title: `Delete ${c.name}?`, message: "Only a collection with no entries can be deleted.", confirmLabel: "Delete", destructive: true }))) return;
    try { await del(`/collections/${slug}`); await site.refresh(); toast("Deleted."); go("/collections"); } catch (e) { toastError(e); }
  }
  const pools = $derived(site.collections.filter((x) => x.slug !== slug).map((x) => ({ value: x.id, label: x.name })));
  const stop = saveShortcut(submit);
  onDestroy(stop);
</script>

{#if !c}
  <div class="flex justify-center py-16"><Spinner /></div>
{:else}
  <PageHeader title={slug ? c.name : "New collection"} icon="stack">
    {#snippet actions()}
      {#if slug}<Button href="#/collections/{slug}">View entries</Button>{/if}
      <Button variant="primary" loading={saving} onclick={submit}>{slug ? "Save changes" : "Create collection"}</Button>
    {/snippet}
  </PageHeader>
  <div class="flex flex-col gap-6 lg:flex-row lg:items-start">
    <div class="flex min-w-0 flex-1 flex-col gap-6">
      <Panel title="Fields">
        <div class="p-5">
          <p class="mb-4 text-sm text-gray-500">What each entry carries besides its title, slug and body. The site reads them as the entry's <code class="rounded-sm bg-gray-100 px-1 font-mono text-xs">frontmatter</code>.</p>
          <SchemaEditor {fields} allowBlocks={false} {errors} path="schema.fields" />
        </div>
      </Panel>
    </div>
    <aside class="flex min-w-0 shrink-0 flex-col gap-4 lg:sticky lg:top-16 lg:w-80">
      <Postbox key="collection-settings" title="Settings">
        <Field label="Name" required error={errors.name}>{#snippet children(id, invalid)}<Input {id} {invalid} bind:value={c.name} oninput={() => { if (!slug) c.slug = slugify(c.name); }} />{/snippet}</Field>
        <Field label="Slug" help="Entries live at /<slug>/<entry>." error={errors.slug}>{#snippet children(id, invalid)}<Input {id} {invalid} mono bind:value={c.slug} />{/snippet}</Field>
        <Switch bind:checked={c.enable_blocks} label="Blocks on entries" description="Entries get a block editor under their fields." />
        <Switch bind:checked={c.api_enabled} label="Available over the API" description="Served on /api/v1 when the site is Website + API." />
      </Postbox>
      <Postbox key="collection-taxonomy" title="Categories & Tags">
        <Field label="Categories from" help="Each entry picks one entry of this collection as its category.">{#snippet children(id)}<Select {id} placeholder="None" options={pools} bind:value={c.categories_collection_id} />{/snippet}</Field>
        <Field label="Tags from" help="Each entry picks any number of its entries as tags.">{#snippet children(id)}<Select {id} placeholder="None" options={pools} bind:value={c.tags_collection_id} />{/snippet}</Field>
      </Postbox>
      {#if slug && session.can("collections:delete")}
        <div><Button variant="danger" size="sm" icon="trash" onclick={remove}>Delete collection</Button></div>
      {/if}
    </aside>
  </div>
{/if}
