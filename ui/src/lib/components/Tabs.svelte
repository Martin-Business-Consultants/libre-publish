<script>
  // Tabs (the markdown editor's Write/Preview look): quiet, the current one filled.
  let { tabs = [], value = $bindable(), class: klass = "" } = $props();
</script>

<div class="flex items-center gap-1 {klass}" role="tablist">
  {#each tabs as t}
    {@const v = typeof t === "object" ? t.value : t}
    <button type="button" role="tab" aria-selected={value === v} onclick={() => (value = v)}
      class="rounded-md px-2.5 py-1 text-xs font-medium leading-4 {value === v ? 'bg-gray-100 text-gray-900' : 'text-gray-500 hover:text-gray-900'}">
      {typeof t === "object" ? t.label : t}
    </button>
  {/each}
</div>
