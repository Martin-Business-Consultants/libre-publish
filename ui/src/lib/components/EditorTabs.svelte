<script>
  // An editor's top row (the Rails editor's): the Edit and SEO tabs on the
  // left; the CLI command and the editor's actions on the right.
  import Icon from "./Icon.svelte";
  import CopyButton from "./CopyButton.svelte";
  let { tab = $bindable("edit"), cli = "", actions = undefined, seoWarning = false } = $props();
  const tabs = [["edit", "Edit", null], ["seo", "SEO", "search"]];
</script>

<div class="flex flex-wrap items-end justify-between gap-x-4 gap-y-2 border-b border-gray-200">
  <div class="flex items-end gap-1" role="tablist">
    {#each tabs as [value, label, icon]}
      <button type="button" role="tab" aria-selected={tab === value} onclick={() => (tab = value)}
        class="-mb-px flex items-center gap-1.5 border-b-2 px-3 pb-2.5 pt-1 text-sm {tab === value ? 'border-gray-900 font-medium text-gray-900' : 'border-transparent text-gray-500 hover:text-gray-900'}">
        {#if icon}<Icon name={icon} />{/if}{label}
        {#if value === "seo" && seoWarning}<span class="size-1.5 rounded-full bg-yellow-500" title="Something to fix"></span>{/if}
      </button>
    {/each}
  </div>
  <div class="flex flex-wrap items-center gap-2 pb-2">
    {#if cli}
      <span class="hidden items-center gap-1 md:flex"><code class="rounded-sm bg-gray-100 px-1 py-0.5 font-mono text-xs text-gray-700">{cli}</code><CopyButton text={cli} /></span>
    {/if}
    {@render actions?.()}
  </div>
</div>
