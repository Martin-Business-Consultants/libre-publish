<script>
  // Signed-out screens (auth.css .public): the site's name over a card.
  import Icon from "../lib/components/Icon.svelte";
  import { session } from "../lib/session.svelte.js";
  import { brand } from "../lib/branding.svelte.js";
  let { children } = $props();
</script>

<div class="flex min-h-dvh flex-col bg-muted/50">
  <header class="px-4 pb-2 pt-12">
    <div class="flex items-center justify-center gap-3">
      {#if brand.current.logo}
        <img src={brand.current.logo.thumb} alt={session.site || "Libre Publish"} class="h-10 w-auto max-w-56 object-contain" />
      {:else}
        <span class="flex size-9 items-center justify-center rounded-md bg-primary text-primary-foreground"><Icon name="home" size="md" /></span>
        <span class="text-xl font-bold tracking-tight">{session.site || "Libre Publish"}</span>
      {/if}
    </div>
  </header>
  <main class="flex-1 px-4 py-8">
    <div class="mx-auto w-full max-w-sm rounded-xl border border-border bg-card p-6 shadow-md">{@render children()}</div>
  </main>
  <footer class="pb-6 text-center text-xs text-muted-foreground">Libre Publish {session.version}</footer>
</div>
