<script>
  // Search everything (⌘K): pages, entries, globals and media as you type,
  // arrows and Enter to open one.
  import Icon from "../components/Icon.svelte";
  import Badge from "../components/Badge.svelte";
  import { post } from "../api.js";
  let { open = $bindable(false) } = $props();
  let el = $state(), input = $state();
  let q = $state(""), results = $state([]), active = $state(0), loading = $state(false);
  let timer;
  $effect(() => {
    if (!el) return;
    if (open && !el.open) { el.showModal(); q = ""; results = []; queueMicrotask(() => input?.focus()); }
    if (!open && el.open) el.close();
  });
  function search() {
    clearTimeout(timer);
    if (!q.trim()) { results = []; return; }
    timer = setTimeout(async () => {
      loading = true;
      try { results = (await post("/search", { query: q.trim() })).results; active = 0; } catch { results = []; }
      loading = false;
    }, 180);
  }
  const target = (r) => r.type === "page" ? `#/pages/edit/${encodeURIComponent(r.path)}` : r.type === "entry" ? `#/collections/${r.collection}/edit/${encodeURIComponent(r.path.split("/").pop())}` : r.type === "global" ? `#/globals/${r.path}` : `#/media?asset=${r.id}`;
  const icons = { page: "document", entry: "newspaper", global: "world", asset: "image" };
  function key(e) {
    if (e.key === "ArrowDown") { e.preventDefault(); active = Math.min(active + 1, results.length - 1); }
    else if (e.key === "ArrowUp") { e.preventDefault(); active = Math.max(active - 1, 0); }
    else if (e.key === "Enter" && results[active]) { location.hash = target(results[active]).slice(1); open = false; }
  }
</script>

<svelte:window onkeydown={(e) => { if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") { e.preventDefault(); open = true; } }} />
<dialog bind:this={el} onclose={() => (open = false)} onclick={(e) => { if (e.target === el) open = false; }}
  class="m-auto mt-[12vh] w-[min(40rem,calc(100vw-2rem))] animate-pop-in overflow-hidden rounded-xl border border-gray-200 bg-surface p-0 text-gray-900 shadow-overlay backdrop:bg-black/40">
  <div class="flex items-center gap-2 border-b border-gray-200 px-4">
    <Icon name="search" class="text-gray-400" />
    <input bind:this={input} bind:value={q} oninput={search} onkeydown={key} placeholder="Search pages, entries, globals, media…" class="h-12 flex-1 border-0 bg-transparent text-base outline-none placeholder:text-gray-400" aria-label="Search everything" />
    <kbd>esc</kbd>
  </div>
  <div class="max-h-[50vh] overflow-y-auto p-2">
    {#if !q.trim()}
      <p class="px-3 py-8 text-center text-sm text-gray-500">Type to search everything.</p>
    {:else if !results.length}
      <p class="px-3 py-8 text-center text-sm text-gray-500">{loading ? "Searching…" : `Nothing matches “${q}”.`}</p>
    {:else}
      {#each results as r, i}
        <a href={target(r)} onclick={() => (open = false)} onmousemove={() => (active = i)}
          class="flex items-start gap-3 rounded-md px-3 py-2 text-sm {i === active ? 'bg-gray-100' : ''}">
          <Icon name={icons[r.type]} class="mt-0.5 text-gray-400" />
          <span class="min-w-0 flex-1">
            <span class="flex items-center gap-2"><span class="truncate font-medium">{r.title}</span>{#if r.status}<Badge status={r.status} />{/if}</span>
            <span class="block truncate text-xs text-gray-500">{r.type === "page" ? "/" + r.path : r.path}{r.snippet ? " · " + r.snippet : ""}</span>
          </span>
        </a>
      {/each}
    {/if}
  </div>
</dialog>
