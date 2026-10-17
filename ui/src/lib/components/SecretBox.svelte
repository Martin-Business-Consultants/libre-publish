<script>
  // A secret shown once: monospace, selectable, with a copy button.
  import CopyButton from "./CopyButton.svelte";
  let { value, note = "" } = $props();
</script>

<div class="flex flex-col gap-2">
  {#if note}<p class="text-sm text-gray-700">{note}</p>{/if}
  <div class="flex items-center gap-2 rounded-md border border-gray-200 bg-gray-50 p-2">
    <code class="min-w-0 flex-1 select-all break-all font-mono text-xs text-gray-900">{value}</code>
    <CopyButton text={value} variant="default" />
  </div>
</div>
