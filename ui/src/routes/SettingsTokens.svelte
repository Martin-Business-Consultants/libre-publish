<script>
  // Service tokens: credentials for machines (the published site, a build,
  // an agent), each on a role.
  import SettingsLayout from "./SettingsLayout.svelte";
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
  import SecretBox from "../lib/components/SecretBox.svelte";
  import { get, post } from "../lib/api.js";
  import { session } from "../lib/session.svelte.js";
  import { confirm } from "../lib/confirm.svelte.js";
  import { toastError } from "../lib/toast.svelte.js";
  let data = $state(null), open = $state(false), form = $state({ name: "PRODUCTION", role: "Production site" }), secret = $state(null), secretOpen = $state(false);
  const load = async () => (data = await get("/service_tokens"));
  load();
  const show = (t) => { secret = t; secretOpen = true; };
  async function create() { try { show((await post("/service_tokens", form)).service_token.token); open = false; load(); } catch (e) { toastError(e); } }
  async function act(t, what) {
    if (what === "rotate" && !(await confirm({ title: `Rotate ${t.name}?`, message: "The old secret stops working at once: update wherever it's stored.", confirmLabel: "Rotate" }))) return;
    if (what === "revoke" && !(await confirm({ title: `Revoke ${t.name}?`, message: "Whatever uses it stops working. This can't be undone.", confirmLabel: "Revoke", destructive: true }))) return;
    try { const r = await post(`/service_tokens/${t.id}/${what}`); if (r.service_token.token) show(r.service_token.token); load(); } catch (e) { toastError(e); }
  }
</script>

<SettingsLayout title="Service tokens">
  <div class="-mt-4 flex flex-wrap items-center justify-between gap-3">
    <p class="text-sm text-gray-500">Credentials for machines. The published site reads with one on the Production site role (PRODUCTION_TOKEN); agents write drafts with one on the Agent role.</p>
    {#if session.can("settings:write")}<Button variant="primary" icon="add" onclick={() => (open = true)}>Issue a token</Button>{/if}
  </div>
  {#if data}
    <DataTable rows={data.service_tokens} columns={[{ label: "Token" }, { label: "Role" }, { label: "Last used" }]} emptyText="No service tokens yet.">
      {#snippet row(t)}
        <Cell>
          <span class="font-medium text-gray-900">{t.name}</span>{#if !t.active}<Badge tone="danger" class="ml-2">Revoked</Badge>{/if}
          <p class="font-mono text-xs text-gray-500">{t.prefix}…</p>
          {#if t.active && session.can("settings:write")}<RowActions><RowAction onclick={() => act(t, "reveal")}>Reveal</RowAction><RowAction onclick={() => act(t, "rotate")}>Rotate</RowAction><RowAction danger onclick={() => act(t, "revoke")}>Revoke</RowAction></RowActions>{/if}
        </Cell>
        <Cell>{t.role.name}</Cell>
        <Cell muted nowrap><Time value={t.last_used_at} class="text-xs" /></Cell>
      {/snippet}
    </DataTable>
  {/if}
</SettingsLayout>
<Dialog bind:open title="Issue a token" size="sm">
  <Field label="Name" help="What it's for: PRODUCTION, PREVIEW, an agent's name.">{#snippet children(id)}<Input {id} mono bind:value={form.name} />{/snippet}</Field>
  <Field label="Role">{#snippet children(id)}<Select {id} bind:value={form.role} options={(data?.roles || []).map((r) => r.name)} />{/snippet}</Field>
  {#snippet actions()}<Button onclick={() => (open = false)}>Cancel</Button><Button variant="primary" onclick={create}>Issue token</Button>{/snippet}
</Dialog>
<Dialog bind:open={secretOpen} title="The token" size="sm">
  {#if secret}<SecretBox value={secret} note="Put it in the environment of what uses it. Never in a repository." />{/if}
  {#snippet actions()}<Button variant="primary" onclick={() => (secretOpen = false)}>Done</Button>{/snippet}
</Dialog>
