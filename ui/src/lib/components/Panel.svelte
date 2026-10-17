<script>
  // A panel (panels.css): a surface with a hairline border, an optional
  // header (title and actions) and a muted footer.
  let { title = "", padded = false, scroll = false, header = undefined, actions = undefined, footer = undefined, children, class: klass = "" } = $props();
</script>

<section class="min-w-0 rounded-xl border border-gray-200 bg-surface {scroll ? 'overflow-x-auto' : ''} {klass}">
  {#if title || header || actions}
    <header class="flex flex-wrap items-center justify-between gap-x-4 gap-y-2 border-b border-gray-200 px-6 py-4">
      {#if header}{@render header()}{:else}<h2 class="text-base font-semibold text-gray-900">{title}</h2>{/if}
      {#if actions}<div class="flex items-center gap-2">{@render actions()}</div>{/if}
    </header>
  {/if}
  <div class={padded ? "p-6" : ""}>{@render children?.()}</div>
  {#if footer}
    <footer class="rounded-b-xl border-t border-gray-200 bg-gray-50 px-5 py-2.5 text-xs leading-4 text-gray-500">{@render footer()}</footer>
  {/if}
</section>
