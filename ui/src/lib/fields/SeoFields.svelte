<script>
  // A record's SEO (the Rails admin's SeoFields): the search result as it
  // would look, then the fields behind it, with lengths that fit.
  import FieldsForm from "./FieldsForm.svelte";
  let { seo, errors = {}, title = "", url = "" } = $props();
  const fields = [
    { name: "meta_title", label: "Meta title", type: "string", help: "Shown as the result's title. Defaults to the page title." },
    { name: "meta_description", label: "Meta description", type: "text", help: "A concise summary that search engines and previews show under the title." },
    { name: "canonical_url", label: "Canonical URL", type: "url" },
    { name: "og_image_id", label: "Social share image", type: "asset" },
    { name: "noindex", label: "Hide from search engines", type: "boolean" },
  ];
  const t = $derived(seo.meta_title || title || "Untitled");
  const d = $derived(seo.meta_description || "");
</script>

<div class="flex flex-col gap-5">
  <div class="rounded-lg border border-border bg-muted/50 p-4">
    <p class="truncate text-xs text-muted-foreground">{url || "/"}</p>
    <p class="truncate text-lg leading-6 text-primary">{t}</p>
    <p class="line-clamp-2 text-sm text-muted-foreground">{d || "No meta description: search engines will pick some text from the page."}</p>
    <p class="mt-2 flex gap-3 text-xs {t.length > 60 ? 'text-amber-700 dark:text-amber-400' : 'text-muted-foreground'}">Title {t.length}/60 <span class={d.length > 160 ? "text-amber-700 dark:text-amber-400" : "text-muted-foreground"}>Description {d.length}/160</span></p>
  </div>
  <FieldsForm {fields} data={seo} path="seo" {errors} />
</div>
