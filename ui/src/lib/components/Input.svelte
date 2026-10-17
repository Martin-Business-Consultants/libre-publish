<script>
  // A text input in the admin's look, optionally with a leading icon.
  import Icon from "./Icon.svelte";
  let { value = $bindable(""), type = "text", icon = null, invalid = false, mono = false, class: klass = "", ref = $bindable(null), ...rest } = $props();
</script>

{#if icon}
  <div class="relative flex items-center">
    <Icon name={icon} class="pointer-events-none absolute left-2.5 text-gray-400" />
    <input bind:this={ref} {type} bind:value class="control pl-8 {mono ? 'font-mono' : ''} {klass}" aria-invalid={invalid || undefined} {...rest} />
  </div>
{:else}
  <input bind:this={ref} {type} bind:value class="control {mono ? 'font-mono' : ''} {klass}" aria-invalid={invalid || undefined} {...rest} />
{/if}
