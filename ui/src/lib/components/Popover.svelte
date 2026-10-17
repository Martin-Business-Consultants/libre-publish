<script>
  // Something that opens under (or beside) its trigger: a menu, a filter. It
  // closes on Escape, on a click outside, and when a link in it is followed.
  let { open = $bindable(false), align = "start", width = "w-56", trigger, children, class: klass = "" } = $props();
  let root = $state();
  function onDocClick(e) { if (open && root && !root.contains(e.target)) open = false; }
  function onKey(e) { if (open && e.key === "Escape") { open = false; root?.querySelector("button")?.focus(); } }
</script>

<svelte:document onclick={onDocClick} onkeydown={onKey} />
<div class="relative {klass}" bind:this={root}>
  {@render trigger({ open, toggle: () => (open = !open) })}
  {#if open}
    <div
      class="absolute top-[calc(100%+0.25rem)] z-30 max-h-[70dvh] max-w-[calc(100vw-1rem)] animate-pop-in overflow-y-auto rounded-xl border border-gray-200 bg-surface p-1 text-gray-900 shadow-overlay {align === 'end' ? 'right-0' : 'left-0'} {width}"
      role="presentation"
      onclick={(e) => { if (e.target.closest("a,[data-close]")) open = false; }}
    >
      {@render children()}
    </div>
  {/if}
</div>
