<script>
  // Settings' frame (settings.css): the sections down the side, the section
  // beside them.
  import PageHeader from "../lib/components/PageHeader.svelte";
  import { router } from "../lib/router.svelte.js";
  let { title, children } = $props();
  const nav = [
    ["Site", [["General", "/settings"], ["Brand", "/settings/brand"], ["Site repository", "/settings/github"]]],
    ["Publishing", [["Deploy", "/settings/deploy"]]],
    ["Access", [["Service tokens", "/settings/tokens"]]],
  ];
</script>

<PageHeader title="Settings" icon="settings-outline" />
<div class="grid items-start gap-6 lg:grid-cols-[13rem_minmax(0,1fr)]">
  <nav class="flex flex-col gap-4 lg:sticky lg:top-16" aria-label="Settings">
    {#each nav as [group, links]}
      <div class="flex flex-col gap-1">
        <span class="px-2 text-xs font-medium text-gray-500">{group}</span>
        {#each links as [label, path]}
          <a href="#{path}" class="block rounded-md px-2 py-1 text-sm {router.path === path ? 'bg-accent-50 font-medium text-accent-700' : 'text-gray-700 hover:bg-gray-100 hover:text-gray-900'}" aria-current={router.path === path ? "page" : undefined}>{label}</a>
        {/each}
      </div>
    {/each}
  </nav>
  <div class="flex min-w-0 flex-col gap-6">
    <h2 class="text-xl font-semibold tracking-tight text-gray-900">{title}</h2>
    {@render children()}
  </div>
</div>
