<script>
  // Settings › Brand: the site's visual identity (the "branding" setting,
  // the Rails core's Settings › Branding). The site reads it from
  // /api/v1/site; the admin wears it (branding.svelte.js), and wears what's
  // being edited as a live preview until it's saved or left.
  import { onDestroy } from "svelte";
  import SettingsLayout from "./SettingsLayout.svelte";
  import Panel from "../lib/components/Panel.svelte";
  import Button from "../lib/components/Button.svelte";
  import Spinner from "../lib/components/Spinner.svelte";
  import Field from "../lib/components/Field.svelte";
  import Input from "../lib/components/Input.svelte";
  import Select from "../lib/components/Select.svelte";
  import AssetField from "../lib/fields/AssetField.svelte";
  import { get, patch } from "../lib/api.js";
  import { save } from "../lib/save.js";
  import { session } from "../lib/session.svelte.js";
  import { brand, hexColor, FONTS, SIZES } from "../lib/branding.svelte.js";

  const KEYS = ["logo_id", "favicon_id", "primary_color", "secondary_color", "font", "border_radius", "box_shadow", "top_bar"];
  const fontOptions = FONTS.map((f) => ({ value: f, label: { Inter: "Inter — clean modern sans", "DM Sans": "DM Sans — geometric", Manrope: "Manrope — soft sans", "Playfair Display": "Playfair Display — editorial serif", Lora: "Lora — calligraphic serif" }[f] }));
  const sizeOptions = SIZES.map((s) => ({ value: s, label: s[0].toUpperCase() + s.slice(1) }));
  const writable = session.can("settings:write");

  let data = $state(null), errors = $state({}), saving = $state(false);
  let logo = $state(null), favicon = $state(null);

  get("/settings/branding").then((r) => {
    const d = r.setting.data || {};
    data = Object.fromEntries(KEYS.map((k) => [k, d[k] == null ? "" : String(d[k])]));
    if (data.top_bar === "match") data.top_bar = "";
  });

  // The chosen logo and favicon, for the preview.
  const assetOf = (id, set) => {
    if (!id) { set(null); return; }
    get(`/assets/${encodeURIComponent(id)}`).then((r) => set(r.asset)).catch(() => set(null));
  };
  $effect(() => { assetOf(data?.logo_id, (a) => (logo = a)); });
  $effect(() => { assetOf(data?.favicon_id, (a) => (favicon = a)); });

  // The admin wears the draft as it's edited.
  $effect(() => {
    if (!data) return;
    brand.preview({ ...$state.snapshot(data), logo, favicon });
  });
  onDestroy(() => brand.reset());

  async function submit() {
    saving = true;
    const body = Object.fromEntries(KEYS.map((k) => [k, data[k] || null]));
    if (body.top_bar === "match") body.top_bar = null;
    const r = await save(() => patch("/settings/branding", { setting: { data: body } }), "branding");
    saving = false; errors = r.errors || {};
    if (r.ok) brand.set((await get("/session")).branding);
  }
</script>

{#snippet colorField(key, label, help, placeholder)}
  <Field {label} {help} error={errors[key]}>
    {#snippet children(id, invalid)}
      <div class="flex items-center gap-2">
        <input type="color" class="h-9 w-11 shrink-0 cursor-pointer rounded-md border border-input bg-background p-1" aria-label="{label}: pick" disabled={!writable}
          value={hexColor(data[key]) || placeholder} oninput={(e) => (data[key] = e.currentTarget.value)} />
        <Input {id} mono {invalid} {placeholder} bind:value={data[key]} disabled={!writable} maxlength="7" />
        {#if data[key]}<Button size="sm" variant="plain" onclick={() => (data[key] = "")} disabled={!writable}>Clear</Button>{/if}
      </div>
    {/snippet}
  </Field>
{/snippet}

<SettingsLayout title="Brand">
  <p class="-mt-4 text-sm text-muted-foreground">The site's visual identity: the logo, colors and type flow into the public site (GET /api/v1/site's <code>branding</code>), and the admin wears them too. What you change is previewed across the admin right away; Save keeps it.</p>
  {#if !data}
    <div class="flex justify-center py-16"><Spinner /></div>
  {:else}
    <fieldset class="flex min-w-0 flex-col gap-6" disabled={!writable}>
      <Panel title="Identity">
        <div class="grid gap-5 p-6 sm:grid-cols-2">
          <Field label="Logo" help="SVG or PNG, from the media library. Shown in the admin's bar and on its sign-in page." error={errors.logo_id}>
            {#snippet children()}<AssetField value={data.logo_id} accept="image" onchange={(v) => (data.logo_id = v || "")} />{/snippet}
          </Field>
          <Field label="Favicon" help="Square works best." error={errors.favicon_id}>
            {#snippet children()}<AssetField value={data.favicon_id} accept="image" onchange={(v) => (data.favicon_id = v || "")} />{/snippet}
          </Field>
        </div>
      </Panel>

      <Panel title="Color">
        <div class="grid gap-5 p-6 sm:grid-cols-2">
          {@render colorField("primary_color", "Primary color", "Buttons, links, focus and what's current. The admin's own when blank.", "#b45309")}
          {@render colorField("secondary_color", "Secondary color", "Tints the grays: surfaces, lines and text. Neutral when blank.", "#1c1917")}
          <Field label="Top bar" help="Dark keeps the admin's top bar dark in light mode too, for a logo drawn for a dark ground." error={errors.top_bar}>
            {#snippet children(id)}<Select {id} bind:value={data.top_bar} placeholder="Match the appearance" options={[{ value: "dark", label: "Dark" }]} />{/snippet}
          </Field>
        </div>
      </Panel>

      <Panel title="Type and surface">
        <div class="grid gap-5 p-6 sm:grid-cols-3">
          <Field label="Font" help="Every word in the admin; the site loads it itself." error={errors.font}>
            {#snippet children(id)}<Select {id} bind:value={data.font} placeholder="Default" options={fontOptions} />{/snippet}
          </Field>
          <Field label="Corners" help="Buttons, fields, panels and menus." error={errors.border_radius}>
            {#snippet children(id)}<Select {id} bind:value={data.border_radius} placeholder="Default" options={sizeOptions} />{/snippet}
          </Field>
          <Field label="Shadow" help="Under panels, and under what floats: menus, dialogs." error={errors.box_shadow}>
            {#snippet children(id)}<Select {id} bind:value={data.box_shadow} placeholder="Default" options={sizeOptions} />{/snippet}
          </Field>
        </div>
      </Panel>
    </fieldset>

    <Panel title="Preview">
      <div class="flex flex-col gap-4 p-6">
        <div class="flex items-center gap-3 rounded-lg border bg-card p-4 shadow-sm">
          {#if brand.current.logo}<img src={brand.current.logo.thumb} alt="" class="h-8 w-auto max-w-40 object-contain" />{/if}
          <span class="text-lg font-semibold">{session.site || "Your site"}</span>
          {#if brand.current.favicon}<img src={brand.current.favicon.thumb} alt="Favicon" class="ml-auto size-6 rounded-sm object-contain" />{/if}
        </div>
        <p class="text-sm text-muted-foreground">The quick brown fox jumps over the lazy dog. <a href="#/settings/brand" class="font-medium text-primary underline-offset-4 hover:underline">A link</a>.</p>
        <div class="flex flex-wrap gap-2">
          <Button variant="primary" icon="check">Primary</Button>
          <Button>Secondary</Button>
          <span class="inline-flex items-center rounded-md bg-muted px-2 text-xs text-muted-foreground">Muted</span>
        </div>
      </div>
    </Panel>

    {#if writable}<div class="flex justify-end"><Button variant="primary" loading={saving} onclick={submit}>Save branding</Button></div>{/if}
  {/if}
</SettingsLayout>
