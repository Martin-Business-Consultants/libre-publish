<script>
  // An editor's top row (the Rails editor's): the Edit and SEO tabs on the
  // left; the CLI command and the editor's actions on the right.
  import * as Tabs from "$lib/components/ui/tabs/index.js";
  import Icon from "./Icon.svelte";
  import CopyButton from "./CopyButton.svelte";
  let { tab = $bindable("edit"), cli = "", actions = undefined, seoWarning = false } = $props();
</script>

<div class="flex flex-wrap items-center justify-between gap-x-4 gap-y-2">
  <Tabs.Root bind:value={tab}>
    <Tabs.List>
      <Tabs.Trigger value="edit">Edit</Tabs.Trigger>
      <Tabs.Trigger value="seo">
        <Icon name="search" />SEO
        {#if seoWarning}<span class="size-1.5 rounded-full bg-amber-500" title="Something to fix"></span>{/if}
      </Tabs.Trigger>
    </Tabs.List>
  </Tabs.Root>
  <div class="flex flex-wrap items-center gap-2">
    {#if cli}
      <span class="hidden items-center gap-1 md:flex"><code class="bg-muted rounded-sm px-1 py-0.5 font-mono text-xs">{cli}</code><CopyButton text={cli} /></span>
    {/if}
    {@render actions?.()}
  </div>
</div>
