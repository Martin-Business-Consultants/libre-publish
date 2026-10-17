<script>
  // A table cell with the table's padding; `muted`, `mono`, `num`, `nowrap`.
  let { muted = false, mono = false, num = false, nowrap = false, class: klass = "", children } = $props();
</script>

<td class="px-3 py-2.5 align-middle {muted ? 'text-gray-500' : 'text-gray-700'} {mono ? 'font-mono text-xs' : ''} {num ? 'text-right tabular-nums' : ''} {nowrap ? 'whitespace-nowrap' : ''} {klass}">{@render children()}</td>
