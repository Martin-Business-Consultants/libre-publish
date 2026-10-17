<script>
  import Icon from "./Icon.svelte";
  let { icon = null, title = "", children = undefined, actions = undefined, class: klass = "" } = $props();
</script>

<div class="flex flex-col items-center gap-2 px-4 py-12 text-center text-gray-500 {klass}">
  {#if icon}<span class="mb-1 flex size-10 items-center justify-center rounded-full bg-gray-100 text-gray-400"><Icon name={icon} size="md" /></span>{/if}
  {#if title}<p class="text-sm font-semibold text-gray-900">{title}</p>{/if}
  {#if children}<div class="max-w-md text-sm">{@render children()}</div>{/if}
  {#if actions}<div class="mt-2 flex items-center gap-2">{@render actions()}</div>{/if}
</div>
