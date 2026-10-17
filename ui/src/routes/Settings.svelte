<script>
  // A settings section: a form over one settings key, with Save.
  import SettingsLayout from "./SettingsLayout.svelte";
  import Panel from "../lib/components/Panel.svelte";
  import Button from "../lib/components/Button.svelte";
  import Spinner from "../lib/components/Spinner.svelte";
  import FieldsForm from "../lib/fields/FieldsForm.svelte";
  import { get, patch } from "../lib/api.js";
  import { save } from "../lib/save.js";
  import { session } from "../lib/session.svelte.js";
  import { site } from "../lib/site.svelte.js";

  let { params = {} } = $props();
  const SECTIONS = {
    general: { title: "General", key: "general", panels: [
      ["The site", [
        { name: "title", label: "Site name", type: "string" },
        { name: "site_base_url", label: "Public site URL", type: "url", help: "Where the site lives (https://example.com). Webhooks, the sitemap and \"View site\" use it." },
        { name: "default_locale", label: "Default locale", type: "string", help: "Pages in other locales are served under a prefix: /fr/…" },
      ]],
      ["How the site is served", [
        { name: "serving", label: "Delivery API", type: "select", options: ["api_only", "website_api"], help: "api_only: everything live is on /api/v1. website_api: only collections marked \"Available over the API\", and pages and globals when switched on below." },
        { name: "api_pages", label: "Serve pages and globals (website_api)", type: "boolean" },
        { name: "cors_origins", label: "Allowed origins", type: "text", help: "Browsers on these origins may call the delivery API and post forms. One per line." },
      ]],
      ["Contact details", [
        { name: "phone", label: "Phone", type: "string" }, { name: "email", label: "Email", type: "string" },
        { name: "address_line1", label: "Address", type: "string" },
        { name: "city", label: "City", type: "string" }, { name: "state", label: "State or region", type: "string" }, { name: "zip", label: "Postal code", type: "string" },
      ]],
    ] },
    brand: { title: "Brand", key: "brand", intro: "The brief agents read before writing copy (cms brand): keep it short and specific.", panels: [
      ["Brand brief", [
        { name: "brand_voice", label: "Voice", type: "text", help: "How the site sounds: plain, warm, technical…" },
        { name: "audience", label: "Audience", type: "text", help: "Who reads it, and what they come for." },
        { name: "key_facts", label: "Facts that must stay accurate", type: "text", help: "Prices, hours, names, claims." },
        { name: "style_notes", label: "House style", type: "text", help: "Spelling, capitalisation, words to use or avoid." },
      ]],
    ] },
    github: { title: "Site repository", key: "github", intro: "The frontend this CMS publishes, so agents working on the site itself find it.", panels: [
      ["Repository", [{ name: "frontend_github_repo", label: "Frontend repository", type: "string", help: "owner/name, not a URL." }]],
    ] },
  };
  // svelte-ignore state_referenced_locally
  const section = SECTIONS[params.section || "general"] || SECTIONS.general;
  let data = $state(null), errors = $state({}), saving = $state(false);
  get(`/settings/${section.key}`).then((r) => (data = r.setting.data || {}));
  async function submit() {
    saving = true;
    const r = await save(() => patch(`/settings/${section.key}`, { setting: { data: $state.snapshot(data) } }));
    saving = false; errors = r.errors || {};
    if (r.ok && section.key === "general") { session.site = data.title; site.refresh(); }
  }
</script>

<SettingsLayout title={section.title}>
  {#if section.intro}<p class="-mt-4 text-sm text-gray-500">{section.intro}</p>{/if}
  {#if !data}
    <div class="flex justify-center py-16"><Spinner /></div>
  {:else}
    {#each section.panels as [title, fields]}
      <Panel {title}><div class="p-6"><FieldsForm {fields} {data} {errors} /></div></Panel>
    {/each}
    {#if session.can("settings:write")}<div class="flex justify-end"><Button variant="primary" loading={saving} onclick={submit}>Save changes</Button></div>{/if}
  {/if}
</SettingsLayout>
