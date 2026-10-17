<script>
  // Pages of a list: where you are, and links to the others with gaps, in
  // shadcn's pagination look (links, since the page is in the address).
  import { withQuery } from "../router.svelte.js";
  import { buttonVariants } from "$lib/components/ui/button/index.js";
  import { cn } from "$lib/utils.js";
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
  const link = (on = false, off = false) => cn(buttonVariants({ variant: on ? "outline" : "ghost", size: "icon-sm" }), off && "pointer-events-none opacity-50");
</script>

{#if pages > 1}
  <nav class="flex flex-wrap items-center justify-between gap-3" aria-label="Pages">
    <p class="text-muted-foreground text-xs">{(page - 1) * per + 1}–{Math.min(page * per, total)} of {total}</p>
    <div class="flex items-center gap-1">
      <a href={withQuery({ page: page - 1 > 1 ? page - 1 : null })} class={link(false, page <= 1)} aria-label="Previous page"><Icon name="arrow-left" /></a>
      {#each list as p}
        {#if p === "…"}<span class="text-muted-foreground px-1.5">…</span>
        {:else}<a href={withQuery({ page: p > 1 ? p : null })} class={link(p === page)} aria-current={p === page ? "page" : undefined}>{p}</a>{/if}
      {/each}
      <a href={withQuery({ page: page + 1 })} class={link(false, page >= pages)} aria-label="Next page"><Icon name="arrow-right" /></a>
    </div>
  </nav>
{/if}
