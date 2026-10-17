<script>
  // Plugins: WebAssembly modules, each asking for capabilities that a person
  // grants (never more than asked), switched on once granted.
  import PageHeader from "../lib/components/PageHeader.svelte";
  import Panel from "../lib/components/Panel.svelte";
  import Button from "../lib/components/Button.svelte";
  import Badge from "../lib/components/Badge.svelte";
  import Checkbox from "../lib/components/Checkbox.svelte";
  import Notice from "../lib/components/Notice.svelte";
  import EmptyState from "../lib/components/EmptyState.svelte";
  import { get, post, patch, del } from "../lib/api.js";
  import { session } from "../lib/session.svelte.js";
  import { confirm } from "../lib/confirm.svelte.js";
  import { toast, toastError } from "../lib/toast.svelte.js";
  let list = $state(null), grants = $state({}), uploading = $state(false), input = $state();
  async function load() {
    list = (await get("/plugins")).plugins;
    grants = Object.fromEntries(list.map((p) => [p.key, { "content:read": !!p.granted["content:read"], storage: !!p.granted.storage, http: [...(p.granted.http || [])] }]));
  }
  load();
  async function upload(file) {
    uploading = true;
    try { const r = await post("/plugins", file); toast(`Installed ${r.plugin.name} ${r.plugin.version}. Grant what it asks for to switch it on.`); load(); } catch (e) { toastError(e); }
    uploading = false;
  }
  async function configure(p, enabled) {
    try { await patch(`/plugins/${p.key}`, { plugin: { granted: grants[p.key], enabled } }); toast(enabled ? `${p.name} is on.` : `${p.name} is off.`); load(); } catch (e) { toastError(e); }
  }
  async function remove(p) {
    if (!(await confirm({ title: `Remove ${p.name}?`, message: "Its stored data is kept, so reinstalling it picks up where it left off.", confirmLabel: "Remove", destructive: true }))) return;
    try { await del(`/plugins/${p.key}`); load(); } catch (e) { toastError(e); }
  }
</script>

<PageHeader title="Plugins" subtitle="Each plugin can do only what it asks for and you grant. None can touch the database, the files, or the network beyond the hosts it names.">
  {#snippet actions()}
    {#if session.can("plugins:write")}
      <input type="file" accept=".wasm,application/wasm" class="hidden" bind:this={input} onchange={(e) => { if (e.currentTarget.files[0]) upload(e.currentTarget.files[0]); e.currentTarget.value = ""; }} />
      <Button icon="add" loading={uploading} onclick={() => input.click()}>Upload plugin</Button>
    {/if}
  {/snippet}
</PageHeader>

{#if list && !list.length}
  <Panel><EmptyState icon="package" title="No plugins">A plugin is one .wasm file, written in Go, Rust, TypeScript or Python against the plugin contract.</EmptyState></Panel>
{:else if list}
  <div class="grid gap-4 xl:grid-cols-2">
    {#each list as p (p.key)}
      {@const want = p.requested}
      {@const g = grants[p.key]}
      <Panel>
        {#snippet header()}
          <div class="min-w-0">
            <h2 class="flex items-center gap-2 text-base font-semibold text-gray-900">{p.name}<span class="text-xs font-normal text-gray-500">{p.version}</span></h2>
            {#if p.description}<p class="text-sm text-gray-500">{p.description}</p>{/if}
          </div>
        {/snippet}
        {#snippet actions()}<Badge tone={p.enabled ? "success" : "neutral"}>{p.enabled ? "On" : "Off"}</Badge>{/snippet}
        <div class="flex flex-col gap-4 p-6">
          <div class="flex flex-col gap-2">
            <h3 class="text-xs font-medium uppercase tracking-wide text-gray-500">Asks for</h3>
            {#if want["content:read"] || want.storage || (want.http || []).length}
              {#if want["content:read"]}<Checkbox bind:checked={g["content:read"]} label="Read live content" description="Pages, entries and globals as the site sees them." />{/if}
              {#if want.storage}<Checkbox bind:checked={g.storage} label="Its own storage" description="A private key–value store no other plugin can see." />{/if}
              {#each want.http || [] as host}
                <Checkbox checked={g.http.includes(host)} onchange={(e) => (g.http = e.currentTarget.checked ? [...g.http, host] : g.http.filter((x) => x !== host))} label="Call {host}" description="Outbound requests to this host only." />
              {/each}
            {:else}<p class="text-sm text-gray-500">Nothing beyond writing to the log.</p>{/if}
          </div>
          {#if p.hooks?.length}<p class="text-sm text-gray-600"><span class="font-medium text-gray-900">Hears:</span> {p.hooks.join(", ")}</p>{/if}
          {#if p.routes?.length}
            <ul class="flex flex-col gap-1">
              {#each p.routes as r}<li class="font-mono text-xs text-gray-600">{r.method} /api/x/{p.key}{r.path}{#if r.public}<Badge class="ml-2">Public</Badge>{/if}</li>{/each}
            </ul>
          {/if}
          {#if p.admin?.screens?.length && p.enabled}
            <div class="flex flex-wrap gap-2">{#each p.admin.screens as s}<Button size="sm" href="#/plugins/{p.key}/{s.id}">{s.title}</Button>{/each}</div>
          {/if}
        </div>
        {#snippet footer()}
          {#if session.can("plugins:write")}
            <div class="flex items-center justify-between gap-2">
              <button type="button" class="font-medium text-red-600 hover:underline" onclick={() => remove(p)}>Remove</button>
              <div class="flex gap-2">
                {#if p.enabled}<Button size="sm" onclick={() => configure(p, false)}>Switch off</Button><Button size="sm" variant="primary" onclick={() => configure(p, true)}>Save grants</Button>
                {:else}<Button size="sm" variant="primary" onclick={() => configure(p, true)}>Grant and switch on</Button>{/if}
              </div>
            </div>
          {/if}
        {/snippet}
      </Panel>
    {/each}
  </div>
{/if}
