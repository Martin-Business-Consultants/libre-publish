<script>
  // Roles: what each can do, edited as a capability matrix (a group per
  // resource, read/write/publish/delete across it).
  import PageHeader from "../lib/components/PageHeader.svelte";
  import DataTable from "../lib/components/DataTable.svelte";
  import Cell from "../lib/components/Cell.svelte";
  import RowActions from "../lib/components/RowActions.svelte";
  import RowAction from "../lib/components/RowAction.svelte";
  import Button from "../lib/components/Button.svelte";
  import Dialog from "../lib/components/Dialog.svelte";
  import Field from "../lib/components/Field.svelte";
  import Input from "../lib/components/Input.svelte";
  import Badge from "../lib/components/Badge.svelte";
  import Notice from "../lib/components/Notice.svelte";
  import { get, post, patch, del } from "../lib/api.js";
  import { save } from "../lib/save.js";
  import { session } from "../lib/session.svelte.js";
  import { confirm } from "../lib/confirm.svelte.js";
  import { toast, toastError } from "../lib/toast.svelte.js";
  let data = $state(null), editing = $state(null), open = $state(false), errors = $state({});
  const load = async () => (data = await get("/roles"));
  load();
  function edit(r) { editing = r ? { ...r, permissions: [...r.permissions] } : { name: "", description: "", permissions: [] }; errors = {}; open = true; }
  async function submit() {
    const body = { role: { name: editing.name, description: editing.description } };
    if (!editing.system) body.role.permissions = editing.permissions;
    const r = await save(() => (editing.id ? patch(`/roles/${editing.id}`, body) : post("/roles", body)));
    errors = r.errors || {};
    if (r.ok) { open = false; load(); }
  }
  async function remove(r) {
    if (!(await confirm({ title: `Delete the ${r.name} role?`, message: "Only a role nobody (and no service token) holds can be deleted.", confirmLabel: "Delete", destructive: true }))) return;
    try { await del(`/roles/${r.id}`); toast("Deleted."); load(); } catch (e) { toastError(e); }
  }
  const has = (c) => editing.permissions.includes(c);
  const flip = (c, on) => (editing.permissions = on ? [...editing.permissions, c] : editing.permissions.filter((x) => x !== c));
  const action = (c) => c.split(":")[1];
</script>

<PageHeader title="Roles">
  {#snippet actions()}{#if session.can("roles:write")}<Button icon="add" onclick={() => edit(null)}>New role</Button>{/if}{/snippet}
</PageHeader>
{#if data}
  <DataTable rows={data.roles} columns={[{ label: "Role" }, { label: "Can" }]}>
    {#snippet row(r)}
      <Cell>
        <span class="font-medium text-gray-900">{r.name}</span>{#if r.system}<Badge tone="info" class="ml-2">Built in</Badge>{/if}
        {#if r.description}<p class="text-xs text-gray-500">{r.description}</p>{/if}
        <RowActions>
          {#if session.can("roles:write")}<RowAction onclick={() => edit(r)}>Edit</RowAction>{/if}
          {#if session.can("roles:delete") && !r.system}<RowAction danger onclick={() => remove(r)}>Delete</RowAction>{/if}
        </RowActions>
      </Cell>
      <Cell muted>{r.system || r.permissions.includes("manage:all") ? "Everything" : `${r.permissions.length} capabilities`}</Cell>
    {/snippet}
  </DataTable>
{/if}

<Dialog bind:open title={editing?.id ? editing.name : "New role"} sheet size="lg">
  {#if editing}
    <Field label="Name" error={errors.name}>{#snippet children(id, invalid)}<Input {id} {invalid} bind:value={editing.name} />{/snippet}</Field>
    <Field label="Description">{#snippet children(id)}<Input {id} bind:value={editing.description} />{/snippet}</Field>
    {#if editing.system}
      <Notice>The administrator role holds every capability, including those plugins add later.</Notice>
    {:else}
      <div class="overflow-hidden rounded-lg border border-gray-200">
        {#each data.catalog as g}
          <div class="flex flex-wrap items-center gap-x-5 gap-y-2 border-b border-gray-100 px-4 py-3 last:border-0">
            <span class="w-28 text-sm font-medium text-gray-900">{g.group}</span>
            {#each g.capabilities as c}
              <label class="flex items-center gap-1.5 text-sm text-gray-700" title={c}><input type="checkbox" checked={has(c)} onchange={(e) => flip(c, e.currentTarget.checked)} />{action(c)}</label>
            {/each}
          </div>
        {/each}
      </div>
    {/if}
  {/if}
  {#snippet actions()}<Button onclick={() => (open = false)}>Cancel</Button><Button variant="primary" onclick={submit}>Save role</Button>{/snippet}
</Dialog>
