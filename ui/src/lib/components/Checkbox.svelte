<script>
  // A checkbox with its label beside it (.choice), and an optional line under.
  let { checked = $bindable(false), label = "", description = "", class: klass = "", ...rest } = $props();
</script>

<label class="flex gap-2 text-sm leading-5 text-gray-700 {description ? 'items-start' : 'items-center'} {klass}">
  <input type="checkbox" bind:checked class={description ? "mt-0.5" : ""} {...rest} />
  <span class="flex flex-col">
    <span>{label}</span>
    {#if description}<span class="text-xs text-gray-500">{description}</span>{/if}
  </span>
</label>
