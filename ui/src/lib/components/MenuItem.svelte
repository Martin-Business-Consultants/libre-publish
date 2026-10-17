<script>
  // One row of a menu (menus.css .menu__item): a link or a button.
  import Icon from "./Icon.svelte";
  let { href = null, icon = null, danger = false, selected = false, onclick = undefined, children, trailing = undefined } = $props();
  const cls = $derived(`flex w-full items-center gap-2 rounded-md px-2.5 py-1.5 text-left text-sm leading-5 hover:bg-gray-100 ${danger ? "text-red-600 hover:bg-red-50" : selected ? "bg-gray-100 font-medium text-gray-900" : "text-gray-700 hover:text-gray-900"}`);
</script>

{#if href}
  <a {href} class={cls} aria-current={selected ? "true" : undefined}>
    {#if icon}<Icon name={icon} />{/if}<span class="min-w-0 flex-1 truncate">{@render children()}</span>{@render trailing?.()}
  </a>
{:else}
  <button type="button" class={cls} data-close {onclick}>
    {#if icon}<Icon name={icon} />{/if}<span class="min-w-0 flex-1 truncate">{@render children()}</span>{@render trailing?.()}
  </button>
{/if}
