<script>
  import PageHeader from "../lib/components/PageHeader.svelte";
  import DataTable from "../lib/components/DataTable.svelte";
  import Cell from "../lib/components/Cell.svelte";
  import RowActions from "../lib/components/RowActions.svelte";
  import RowAction from "../lib/components/RowAction.svelte";
  import Button from "../lib/components/Button.svelte";
  import Dialog from "../lib/components/Dialog.svelte";
  import Field from "../lib/components/Field.svelte";
  import Input from "../lib/components/Input.svelte";
  import Select from "../lib/components/Select.svelte";
  import Badge from "../lib/components/Badge.svelte";
  import Time from "../lib/components/Time.svelte";
  import { get, post, patch, del } from "../lib/api.js";
  import { save } from "../lib/save.js";
  import { router } from "../lib/router.svelte.js";
  import { session } from "../lib/session.svelte.js";
  import { confirm } from "../lib/confirm.svelte.js";
  import { toast, toastError } from "../lib/toast.svelte.js";
  let users = $state(null), roles = $state([]), open = $state(router.query.get("new") === "1"), form = $state({ name: "", email: "", password: "", role_id: "" }), errors = $state({});
  async function load() {
    const [u, r] = await Promise.all([get("/users"), get("/roles").catch(() => ({ roles: [] }))]);
    users = u.users; roles = r.roles;
    if (!form.role_id) form.role_id = String(roles.find((x) => x.name === "Editor")?.id || roles[0]?.id || "");
  }
  load();
  async function add() {
    const r = await save(() => post("/users", { user: { ...form, role_id: Number(form.role_id) } }));
    errors = r.errors || {};
    if (r.ok) { open = false; form = { name: "", email: "", password: "", role_id: form.role_id }; load(); }
  }
  async function setRole(u, id) { try { await patch(`/users/${u.id}`, { user: { role_id: Number(id) } }); toast(`${u.name} is now ${roles.find((r) => r.id == id)?.name}.`); load(); } catch (e) { toastError(e); } }
  async function remove(u) {
    if (!(await confirm({ title: `Remove ${u.name}?`, message: "They can't sign in any more, and their API token stops working. What they wrote stays.", confirmLabel: "Remove", destructive: true }))) return;
    try { await del(`/users/${u.id}`); toast("Removed."); load(); } catch (e) { toastError(e); }
  }
</script>

<PageHeader title="Users">
  {#snippet actions()}{#if session.can("users:write")}<Button icon="add" onclick={() => (open = true)}>New user</Button>{/if}{/snippet}
</PageHeader>
{#if users}
  <DataTable rows={users} columns={[{ label: "Name" }, { label: "Email" }, { label: "Role" }, { label: "Since" }]}>
    {#snippet row(u)}
      <Cell>
        <span class="flex items-center gap-2">
          <span class="flex size-7 items-center justify-center rounded-full bg-gray-100 text-xs font-semibold text-gray-600">{(u.name || "?").split(" ").map((x) => x[0]).slice(0, 2).join("").toUpperCase()}</span>
          <span class="font-medium text-gray-900">{u.name}</span>
          {#if u.id === session.me.user.id}<Badge tone="info">You</Badge>{/if}
          {#if u.two_factor}<Badge>2FA</Badge>{/if}
        </span>
        {#if session.can("users:delete") && u.id !== session.me.user.id}<RowActions><RowAction danger onclick={() => remove(u)}>Remove</RowAction></RowActions>{/if}
      </Cell>
      <Cell muted>{u.email}</Cell>
      <Cell>
        {#if session.can("users:write") && u.id !== session.me.user.id}
          <Select class="w-44" value={String(u.role?.id || "")} options={roles.map((r) => ({ value: String(r.id), label: r.name }))} onchange={(e) => setRole(u, e.currentTarget.value)} aria-label="Role" />
        {:else}{u.role?.name || "—"}{/if}
      </Cell>
      <Cell muted nowrap><Time value={u.created_at} class="text-xs" /></Cell>
    {/snippet}
  </DataTable>
{/if}
<Dialog bind:open title="Add a person" size="sm">
  <Field label="Name" error={errors.name}>{#snippet children(id, invalid)}<Input {id} {invalid} bind:value={form.name} autocomplete="off" />{/snippet}</Field>
  <Field label="Email" help="What they sign in with." error={errors.email}>{#snippet children(id, invalid)}<Input {id} {invalid} type="email" bind:value={form.email} autocomplete="off" />{/snippet}</Field>
  <Field label="Password" help="At least 10 characters. Share it with them safely; they can change it." error={errors.password}>{#snippet children(id, invalid)}<Input {id} {invalid} type="password" bind:value={form.password} autocomplete="new-password" />{/snippet}</Field>
  <Field label="Role" error={errors.role_id}>{#snippet children(id)}<Select {id} bind:value={form.role_id} options={roles.map((r) => ({ value: String(r.id), label: r.name }))} />{/snippet}</Field>
  {#snippet actions()}<Button onclick={() => (open = false)}>Cancel</Button><Button variant="primary" onclick={add}>Add person</Button>{/snippet}
</Dialog>
