<script>
  // Before a first publish: suggestions, each fixable where it's shown, none
  // of them in the way (WordPress's pre-publish checks). After it: where it
  // now lives, to copy or open, and Add another. Whether the checks show is
  // the person's preference.
  import * as Sheet from "$lib/components/ui/sheet/index.js";
  import Dialog from "../components/Dialog.svelte";
  import Button from "../components/Button.svelte";
  import Input from "../components/Input.svelte";
  import Textarea from "../components/Textarea.svelte";
  import Checkbox from "../components/Checkbox.svelte";
  import CopyButton from "../components/CopyButton.svelte";
  import Icon from "../components/Icon.svelte";
  import AssetField from "./AssetField.svelte";
  import { prefs } from "../prefs.svelte.js";
  import { dateTime } from "../format.js";

  let { open = $bindable(false), published = $bindable(false), record, noun = "page", url = "", addHref = "", hasContent = true, onpublish } = $props();
  const seo = $derived(record.seo || {});
  const title = $derived(seo.meta_title || record.title || "");
  const checks = $derived([
    { key: "title", ok: !!record.title?.trim(), label: "A title", hint: `The ${noun} has no title.` },
    { key: "content", ok: hasContent, label: "Some content", hint: `The ${noun} is empty: add blocks${noun === "entry" ? " or a body" : ""} first.` },
    { key: "description", ok: !!seo.meta_description?.trim() && seo.meta_description.length <= 160, label: "A meta description", hint: seo.meta_description?.length > 160 ? `It's ${seo.meta_description.length} characters; search results show about 160.` : "Search results and link previews show it under the title.", fix: "description" },
    { key: "title_length", ok: title.length <= 60, label: "A title that fits search results", hint: `It's ${title.length} characters; results show about 60. Give it a shorter search title.`, fix: "meta_title" },
    { key: "image", ok: !!seo.og_image_id, label: "A share image", hint: "Shown when the link is shared. Optional.", fix: "image", optional: true },
  ]);
  const open_ = $derived(checks.filter((c) => !c.ok));
  const scheduled = $derived(record.publish_at && new Date(record.publish_at) > new Date());
  let always = $state(prefs.get("publish_checks", true));
  const ensureSeo = () => { if (!record.seo) record.seo = {}; };
</script>

<Sheet.Root bind:open>
  <Sheet.Content class="w-full sm:max-w-md">
    <Sheet.Header>
      <Sheet.Title>{scheduled ? "Ready to schedule?" : "Ready to publish?"}</Sheet.Title>
      <Sheet.Description>
        {#if scheduled}It goes live on {dateTime(record.publish_at)}.{:else}It goes live as soon as you publish.{/if}
        {open_.length ? " A few suggestions first; none of them stop you." : " Everything looks good."}
      </Sheet.Description>
    </Sheet.Header>
    <div class="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto px-4">
      {#each checks as c (c.key)}
        <div class="flex gap-3 rounded-lg border p-3 {c.ok ? '' : c.optional ? 'border-dashed' : 'border-amber-500/40 bg-amber-500/5'}">
          <Icon name={c.ok ? "check-circle" : "help-circle"} size="md" class={c.ok ? "text-emerald-600 dark:text-emerald-400" : c.optional ? "text-muted-foreground" : "text-amber-600 dark:text-amber-400"} />
          <div class="flex min-w-0 flex-1 flex-col gap-2">
            <p class="text-sm font-medium">{c.label}</p>
            {#if !c.ok}
              <p class="text-muted-foreground text-xs">{c.hint}</p>
              {#if c.fix === "description"}
                <Textarea rows={3} placeholder="One or two sentences on what this {noun} is about" value={seo.meta_description || ""} oninput={(e) => { ensureSeo(); record.seo.meta_description = e.currentTarget.value; }} aria-label="Meta description" />
                <p class="text-muted-foreground text-xs">{(seo.meta_description || "").length}/160</p>
              {:else if c.fix === "meta_title"}
                <Input placeholder="A shorter title for search results" value={seo.meta_title || ""} oninput={(e) => { ensureSeo(); record.seo.meta_title = e.currentTarget.value; }} aria-label="Search title" />
              {:else if c.fix === "image"}
                <AssetField value={seo.og_image_id} onchange={(v) => { ensureSeo(); record.seo.og_image_id = v; }} />
              {/if}
            {/if}
          </div>
        </div>
      {/each}
    </div>
    <Sheet.Footer class="gap-3">
      <Checkbox label="Always show these checks before publishing" bind:checked={always} onchange={(on) => prefs.set("publish_checks", on)} />
      <div class="flex justify-end gap-2">
        <Button onclick={() => (open = false)}>Cancel</Button>
        <Button variant="primary" onclick={() => { open = false; onpublish(); }}>{scheduled ? "Schedule" : open_.some((c) => !c.optional) ? "Publish anyway" : "Publish"}</Button>
      </div>
    </Sheet.Footer>
  </Sheet.Content>
</Sheet.Root>

<Dialog bind:open={published} title={scheduled ? `“${record.title}” is scheduled` : `“${record.title}” is live`} size="sm">
  <p class="text-muted-foreground text-sm">{scheduled ? `It goes live on ${dateTime(record.publish_at)}.` : "It's on the site, or will be once the site rebuilds."}</p>
  {#if url}
    <div class="bg-muted/50 flex items-center gap-2 rounded-md border p-2">
      <code class="min-w-0 flex-1 truncate font-mono text-xs">{url}</code>
      <CopyButton text={url} label="Copy" />
    </div>
  {/if}
  {#snippet actions()}
    {#if addHref}<Button href={addHref} icon="add" onclick={() => (published = false)}>Add another</Button>{/if}
    {#if url?.startsWith("http")}<Button variant="primary" href={url} target="_blank" rel="noopener" icon="external">View {noun}</Button>{/if}
    <Button onclick={() => (published = false)}>Close</Button>
  {/snippet}
</Dialog>
