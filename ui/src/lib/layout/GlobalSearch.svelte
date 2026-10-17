<script>
  // Search everything (⌘K), shadcn's Command dialog: pages, entries, globals
  // and media as you type, arrows and Enter to open one.
  import * as Command from "$lib/components/ui/command/index.js";
  import Icon from "../components/Icon.svelte";
  import Badge from "../components/Badge.svelte";
  import { post } from "../api.js";
  let { open = $bindable(false) } = $props();
  let q = $state(""), results = $state([]), loading = $state(false);
  let timer;
  $effect(() => { if (open) { q = ""; results = []; } });
  function search() {
    clearTimeout(timer);
    if (!q.trim()) { results = []; return; }
    timer = setTimeout(async () => {
      loading = true;
      try { results = (await post("/search", { query: q.trim() })).results; } catch { results = []; }
      loading = false;
    }, 180);
  }
  const target = (r) => r.type === "page" ? `#/pages/edit/${encodeURIComponent(r.path)}` : r.type === "entry" ? `#/collections/${r.collection}/edit/${encodeURIComponent(r.path.split("/").pop())}` : r.type === "global" ? `#/globals/${r.path}` : `#/media?asset=${r.id}`;
  const icons = { page: "document", entry: "newspaper", global: "world", asset: "image" };
  function go(r) { location.hash = target(r).slice(1); open = false; }
</script>

<svelte:window onkeydown={(e) => { if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") { e.preventDefault(); open = true; } }} />
<Command.Dialog bind:open shouldFilter={false} title="Search everything" description="Pages, entries, globals and media">
  <Command.Input bind:value={q} oninput={search} placeholder="Search pages, entries, globals, media…" />
  <Command.List class="max-h-[50vh]">
    {#if !q.trim()}
      <p class="text-muted-foreground py-6 text-center text-sm">Type to search everything.</p>
    {:else if !results.length}
      <p class="text-muted-foreground py-6 text-center text-sm">{loading ? "Searching…" : `Nothing matches “${q}”.`}</p>
    {:else}
      <Command.Group>
        {#each results as r, i (target(r) + i)}
          <Command.Item value={target(r) + i} onSelect={() => go(r)} class="items-start">
            <Icon name={icons[r.type]} class="mt-0.5" />
            <span class="min-w-0 flex-1">
              <span class="flex items-center gap-2"><span class="truncate font-medium">{r.title}</span>{#if r.status}<Badge status={r.status} />{/if}</span>
              <span class="text-muted-foreground block truncate text-xs">{r.type === "page" ? "/" + r.path : r.path}{r.snippet ? " · " + r.snippet : ""}</span>
            </span>
          </Command.Item>
        {/each}
      </Command.Group>
    {/if}
  </Command.List>
</Command.Dialog>
