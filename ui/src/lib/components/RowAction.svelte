<script>
  let { href = null, danger = false, onclick = undefined, children } = $props();
  const cls = $derived(`${danger ? "text-red-600 hover:text-red-700" : "text-gray-500 hover:text-gray-900"} hover:underline`);
</script>

{#if href}<a {href} class={cls}>{@render children()}</a>{:else}<button type="button" class={cls} {onclick}>{@render children()}</button>{/if}
