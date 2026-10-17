<script>
  import SettingsLayout from "./SettingsLayout.svelte";
  import Panel from "../lib/components/Panel.svelte";
  import Button from "../lib/components/Button.svelte";
  import Badge from "../lib/components/Badge.svelte";
  import Notice from "../lib/components/Notice.svelte";
  import Time from "../lib/components/Time.svelte";
  import Spinner from "../lib/components/Spinner.svelte";
  import FieldsForm from "../lib/fields/FieldsForm.svelte";
  import { get, patch, post } from "../lib/api.js";
  import { save } from "../lib/save.js";
  import { session } from "../lib/session.svelte.js";
  import { toast, toastError } from "../lib/toast.svelte.js";
  let d = $state(null), cfg = $state({}), saving = $state(false), deploying = $state(false);
  async function load() { d = (await get("/deploy")).deploy; cfg = { ...(d.config || {}) }; }
  load();
  async function submit() { saving = true; const r = await save(() => patch("/deploy", { deploy: $state.snapshot(cfg) })); saving = false; if (r.ok) load(); }
  async function now() {
    deploying = true;
    try { const r = await post("/deploy/trigger"); toast(`Deploy ${r.deploy.status}.`); load(); } catch (e) { toastError(e); load(); }
    deploying = false;
  }
</script>

<SettingsLayout title="Deploy">
  <p class="-mt-4 text-sm text-gray-500">Publishing rebuilds the site through a build hook (Netlify, Cloudflare Pages, Vercel, a GitHub workflow), a few seconds after the last change.</p>
  {#if !d}<div class="flex justify-center py-16"><Spinner /></div>{:else}
    {#if d.last?.status}
      <Notice tone={d.last.status === "success" ? "success" : d.last.status === "disabled" ? "info" : "danger"}>
        Last deploy: <strong class="font-semibold">{d.last.status}</strong>, <Time value={d.last.at} />{d.last.reason ? ` (${d.last.reason})` : ""}.{#if d.last.error} {d.last.error}{/if}
      </Notice>
    {/if}
    <Panel title="Build hook">
      {#snippet actions()}{#if d.configured}<Badge tone="success">Configured</Badge>{:else}<Badge>Not set</Badge>{/if}{/snippet}
      <div class="p-6"><FieldsForm data={cfg} fields={[
        { name: "hook_url", label: "Build hook URL", type: "url", help: "The CMS POSTs here to rebuild the site." },
        { name: "debounce_seconds", label: "Wait before building (seconds)", type: "integer", help: "Changes inside the wait go out as one build. 30 by default." },
        { name: "enabled", label: "Rebuild on publish", type: "boolean" },
      ]} /></div>
    </Panel>
    <div class="flex justify-end gap-2">
      {#if session.can("pages:publish")}<Button icon="refresh" loading={deploying} onclick={now}>Rebuild now</Button>{/if}
      {#if session.can("settings:write")}<Button variant="primary" loading={saving} onclick={submit}>Save changes</Button>{/if}
    </div>
  {/if}
</SettingsLayout>
