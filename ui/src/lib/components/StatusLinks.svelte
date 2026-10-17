<script>
  // A list's status filter, WordPress's "All (12) | Published (8) | Draft
  // (4)", drawn as quiet tabs, the current one filled. Each is a link that
  // swaps one query parameter, so a filtered list is bookmarkable.
  import { router, withQuery } from "../router.svelte.js";
  let { param = "status", options = [] } = $props();
  const current = $derived(router.query.get(param) || "");
</script>

<ul class="flex flex-wrap items-center gap-1 text-sm leading-5" role="list">
  {#each options as o}
    {@const chosen = (o.value || "") === current}
    <li>
      <a
        href={withQuery({ [param]: o.value || null })}
        class="inline-flex h-7 items-center gap-1.5 rounded-md px-2.5 {chosen ? 'bg-gray-100 font-medium text-gray-900' : 'text-gray-500 hover:bg-gray-50 hover:text-gray-900'}"
        aria-current={chosen ? "page" : undefined}
      >
        {o.label}
        {#if o.count != null}<span class="text-xs tabular-nums {chosen ? 'text-gray-500' : 'text-gray-400'}">{o.count}</span>{/if}
      </a>
    </li>
  {/each}
</ul>
