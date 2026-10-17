<script>
  // Signed-out screens (auth.css .public): the site's name over a card.
  import Icon from "../lib/components/Icon.svelte";
  import { session } from "../lib/session.svelte.js";
  let { children } = $props();
</script>

<div class="flex min-h-dvh flex-col bg-gray-50">
  <header class="px-4 pb-2 pt-12">
    <div class="flex items-center justify-center gap-3">
      <span class="flex size-9 items-center justify-center rounded-md bg-accent-600 text-on-accent"><Icon name="home" size="md" /></span>
      <span class="text-xl font-bold tracking-tight">{session.site || "Libre Publish"}</span>
    </div>
  </header>
  <main class="flex-1 px-4 py-8">
    <div class="mx-auto w-full max-w-sm rounded-xl border border-gray-200 bg-surface p-6 shadow-overlay">{@render children()}</div>
  </main>
  <footer class="pb-6 text-center text-xs text-gray-400">Libre Publish {session.version}</footer>
</div>
