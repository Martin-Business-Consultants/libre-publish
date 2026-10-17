<script>
  // A status badge (badges.css): uppercase, the tone from the status the way
  // the Rails admin chose it, or given.
  import { tone as toneOf, humanize } from "../format.js";
  let { status = "", tone = null, children = undefined, class: klass = "" } = $props();
  const t = $derived(tone || toneOf(status));
  const tones = {
    neutral: "bg-gray-100 text-gray-700",
    info: "bg-accent-50 text-accent-700",
    success: "bg-green-50 text-green-700",
    warning: "bg-yellow-50 text-yellow-800",
    danger: "bg-red-50 text-red-700",
  };
</script>

<span class="inline-flex items-center gap-1 whitespace-nowrap rounded-sm px-1.5 py-0.5 text-xs font-semibold uppercase leading-4 tracking-wide {tones[t]} {klass}">
  {#if children}{@render children()}{:else}{humanize(status)}{/if}
</span>
