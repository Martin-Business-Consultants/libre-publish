<script>
  // The admin's switch (forms.css .switch), with its label and description.
  let { checked = $bindable(false), label = "", description = "", disabled = false, onchange = undefined, id = undefined } = $props();
  const uid = $props.id();
  const sid = $derived(id || `s-${uid}`);
</script>

<div class="flex items-center gap-3">
  <span class="relative inline-flex h-5 w-9 shrink-0">
    <input id={sid} type="checkbox" role="switch" class="peer absolute size-0 opacity-0" bind:checked {disabled} {onchange} />
    <label
      for={sid}
      class="absolute inset-0 cursor-pointer rounded-full bg-gray-300 transition-colors peer-checked:bg-accent-600 peer-focus-visible:outline-2 peer-focus-visible:outline-offset-2 peer-focus-visible:outline-accent-500 peer-disabled:cursor-not-allowed peer-disabled:opacity-50 hover:bg-gray-400 peer-checked:hover:bg-accent-700
        before:absolute before:left-0.5 before:top-0.5 before:size-4 before:rounded-full before:bg-surface before:shadow-[0_1px_2px_rgb(0_0_0/0.2)] before:transition-transform before:content-[''] peer-checked:before:translate-x-4 peer-checked:before:bg-on-accent"
    ><span class="sr-only">{label}</span></label>
  </span>
  {#if label || description}
    <label for={sid} class="flex cursor-pointer flex-col text-sm leading-5">
      {#if label}<span class="font-medium text-gray-900">{label}</span>{/if}
      {#if description}<span class="text-xs text-gray-500">{description}</span>{/if}
    </label>
  {/if}
</div>
