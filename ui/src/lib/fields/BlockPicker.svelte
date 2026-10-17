<script>
  // Adding a block: the block types by category, as cards with their
  // descriptions, and a search across them.
  import Dialog from "../components/Dialog.svelte";
  import Input from "../components/Input.svelte";
  import { blockTypes } from "../blocks.svelte.js";
  let { open = $bindable(false), allowed = null, onpick } = $props();
  let q = $state("");
  const choices = $derived(
    blockTypes.list.filter((t) => !t.deprecated && (!allowed || !allowed.length || allowed.includes(t.slug)))
      .filter((t) => !q || (t.label + " " + (t.description || "") + " " + t.slug).toLowerCase().includes(q.toLowerCase())),
  );
  const groups = $derived(Object.entries(choices.reduce((g, t) => ((g[t.category || "Other"] ||= []).push(t), g), {})));
  $effect(() => { if (open) { q = ""; blockTypes.load(); } });
</script>

<Dialog bind:open title="Add a block" size="lg">
  <Input icon="search" placeholder="Search blocks…" bind:value={q} autofocus />
  <div class="flex flex-col gap-5">
    {#each groups as [cat, types]}
      <section class="flex flex-col gap-2">
        <h3 class="text-xs font-medium uppercase tracking-wide text-muted-foreground">{cat}</h3>
        <ul class="grid gap-2 sm:grid-cols-2">
          {#each types as t (t.slug)}
            <li>
              <button type="button" onclick={() => { onpick(t); open = false; }}
                class="flex h-full w-full flex-col items-start gap-0.5 rounded-lg border border-border bg-card px-3 py-2.5 text-left hover:border-ring hover:bg-muted/50">
                <span class="text-sm font-medium text-foreground">{t.label}</span>
                {#if t.description}<span class="line-clamp-2 text-xs text-muted-foreground">{t.description}</span>{/if}
              </button>
            </li>
          {/each}
        </ul>
      </section>
    {:else}
      <p class="py-8 text-center text-sm text-muted-foreground">{blockTypes.list.length ? "No block matches." : "No block types yet: install the starter pack under Tools › Block types."}</p>
    {/each}
  </div>
</Dialog>
