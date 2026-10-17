<script>
  import PageHeader from "../lib/components/PageHeader.svelte";
  import Panel from "../lib/components/Panel.svelte";
  import Field from "../lib/components/Field.svelte";
  import Input from "../lib/components/Input.svelte";
  import Button from "../lib/components/Button.svelte";
  import SecretBox from "../lib/components/SecretBox.svelte";
  import { patch, post } from "../lib/api.js";
  import { save } from "../lib/save.js";
  import { session } from "../lib/session.svelte.js";
  import { confirm } from "../lib/confirm.svelte.js";
  import { toastError } from "../lib/toast.svelte.js";
  const me = session.me.user;
  let name = $state(me.name), current = $state(""), next = $state(""), errors = $state({}), token = $state(null);
  async function saveName() { const r = await save(() => patch(`/users/${me.id}`, { user: { name } })); if (r.ok) session.me.user.name = name; }
  async function savePassword() {
    const r = await save(() => patch(`/users/${me.id}`, { user: { current_password: current, password: next } }));
    errors = r.errors || {};
    if (r.ok) { current = ""; next = ""; }
  }
  async function rotate() {
    if (!(await confirm({ title: "Rotate your API token?", message: "The old one stops working at once, on every machine that has it.", confirmLabel: "Rotate" }))) return;
    try { token = (await post("/api_tokens/rotate")).token.token; } catch (e) { toastError(e); }
  }
</script>

<PageHeader title="Your account" subtitle={me.email} />
<div class="grid items-start gap-6 lg:grid-cols-2">
  <Panel title="Profile">
    <div class="flex flex-col gap-5 p-6">
      <Field label="Name">{#snippet children(id)}<Input {id} bind:value={name} />{/snippet}</Field>
      <div class="flex justify-end"><Button variant="primary" onclick={saveName}>Save</Button></div>
    </div>
  </Panel>
  <Panel title="Password">
    <div class="flex flex-col gap-5 p-6">
      <Field label="Current password" error={errors.current_password}>{#snippet children(id, invalid)}<Input {id} {invalid} type="password" bind:value={current} autocomplete="current-password" />{/snippet}</Field>
      <Field label="New password" help="At least 10 characters. Your other sessions are signed out." error={errors.password}>{#snippet children(id, invalid)}<Input {id} {invalid} type="password" bind:value={next} autocomplete="new-password" />{/snippet}</Field>
      <div class="flex justify-end"><Button variant="primary" onclick={savePassword}>Change password</Button></div>
    </div>
  </Panel>
  <Panel title="API token">
    <div class="flex flex-col gap-4 p-6">
      <p class="text-sm text-gray-600">For the <code class="rounded-sm bg-gray-100 px-1 font-mono text-xs">cms</code> CLI where <code class="rounded-sm bg-gray-100 px-1 font-mono text-xs">cms login</code> can't open a browser. It acts as you, with your role.</p>
      {#if token}<SecretBox value={token} note="Shown once." />{/if}
      <div><Button icon="refresh" onclick={rotate}>Rotate and show</Button></div>
    </div>
  </Panel>
</div>
