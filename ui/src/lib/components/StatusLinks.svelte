<script>
  // A list's status filter, WordPress's "All (12) | Published (8) | Draft
  // (4)", drawn as shadcn's tabs list. Each is a link that swaps one query
  // parameter, so a filtered list is bookmarkable.
  import { router, withQuery } from "../router.svelte.js";
  let { param = "status", options = [] } = $props();
  const current = $derived(router.query.get(param) || "");
</script>

<ul class="bg-muted text-muted-foreground inline-flex w-fit flex-wrap items-center rounded-lg p-[3px]" role="list">
  {#each options as o}
    {@const chosen = (o.value || "") === current}
    <li>
      <a
        href={withQuery({ [param]: o.value || null })}
        class="inline-flex h-7 items-center gap-1.5 rounded-md px-2.5 text-sm font-medium transition-colors {chosen ? 'bg-background text-foreground shadow-sm dark:bg-input/30' : 'hover:text-foreground'}"
        aria-current={chosen ? "page" : undefined}
      >
        {o.label}
        {#if o.count != null}<span class="text-muted-foreground text-xs tabular-nums">{o.count}</span>{/if}
      </a>
    </li>
  {/each}
</ul>
