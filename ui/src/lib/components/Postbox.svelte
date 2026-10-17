<script>
  // A postbox (the editor's side boxes, WordPress's): a panel that folds
  // under its title, remembering whether it was open.
  import Icon from "./Icon.svelte";
  let { key = "", title, flush = false, children, class: klass = "" } = $props();
  let open = $state(true);
  $effect.pre(() => {
    try { if (key && localStorage.getItem("lp-postbox-" + key) === "closed") open = false; } catch {}
  });
  function remember() {
    try { if (key) localStorage.setItem("lp-postbox-" + key, open ? "open" : "closed"); } catch {}
  }
</script>

<details class="group min-w-0 rounded-xl border border-gray-200 bg-surface {klass}" bind:open ontoggle={remember}>
  <summary class="flex select-none items-center justify-between gap-2 px-5 py-3.5 group-open:border-b group-open:border-gray-200">
    <h2 class="text-base font-semibold text-gray-900">{title}</h2>
    <Icon name="caret-down" class="text-gray-400 transition-transform group-[:not([open])]:-rotate-90" />
  </summary>
  <div class={flush ? "text-sm" : "flex flex-col gap-5 p-5 text-sm"}>{@render children()}</div>
</details>
