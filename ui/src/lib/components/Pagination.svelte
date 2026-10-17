<script>
  // Pages of a list: where you are, and links to the others with gaps.
  import { router, withQuery } from "../router.svelte.js";
  import Icon from "./Icon.svelte";
  let { page = 1, per = 25, total = 0 } = $props();
  const pages = $derived(Math.max(1, Math.ceil(total / per)));
  const list = $derived.by(() => {
    const out = [];
    for (let p = 1; p <= pages; p++) {
      if (p === 1 || p === pages || Math.abs(p - page) <= 1) out.push(p);
      else if (out[out.length - 1] !== "…") out.push("…");
    }
    return out;
  });
  const link = "inline-flex h-7 min-w-7 items-center justify-center rounded-md px-2 text-sm";
</script>

{#if pages > 1}
  <nav class="flex flex-wrap items-center justify-between gap-3" aria-label="Pages">
    <p class="text-xs text-gray-500">{(page - 1) * per + 1}–{Math.min(page * per, total)} of {total}</p>
    <div class="flex items-center gap-1">
      <a href={withQuery({ page: page - 1 > 1 ? page - 1 : null })} class="{link} text-gray-600 hover:bg-gray-100 {page <= 1 ? 'pointer-events-none opacity-50' : ''}" aria-label="Previous page"><Icon name="arrow-left" /></a>
      {#each list as p}
        {#if p === "…"}<span class="px-1.5 text-gray-500">…</span>
        {:else}<a href={withQuery({ page: p > 1 ? p : null })} class="{link} {p === page ? 'bg-gray-100 font-medium text-gray-900' : 'text-gray-600 hover:bg-gray-100'}" aria-current={p === page ? "page" : undefined}>{p}</a>{/if}
      {/each}
      <a href={withQuery({ page: page + 1 })} class="{link} text-gray-600 hover:bg-gray-100 {page >= pages ? 'pointer-events-none opacity-50' : ''}" aria-label="Next page"><Icon name="arrow-right" /></a>
    </div>
  </nav>
{/if}
