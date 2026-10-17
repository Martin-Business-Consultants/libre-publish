<script>
  // A quick filter (Fizzy's, as the Rails admin had it): a select-like
  // button showing the choice, opening a menu of the others. Each choice is
  // a link that swaps one query parameter.
  import Popover from "./Popover.svelte";
  import Icon from "./Icon.svelte";
  import { router, withQuery } from "../router.svelte.js";
  let { title, param, options = [] } = $props();
  const current = $derived(router.query.get(param) || "");
  const chosen = $derived(options.find((o) => (o.value || "") === current) || options[0]);
  let open = $state(false);
</script>

<Popover bind:open width="w-56">
  {#snippet trigger({ toggle })}
    <button type="button" onclick={toggle} aria-haspopup="listbox" aria-expanded={open} {title}
      class="inline-flex h-8 max-w-80 items-center gap-1.5 rounded-md border px-3 text-sm font-semibold {current ? 'border-accent-200 bg-accent-50 text-accent-700' : 'border-gray-300 bg-surface text-gray-900 hover:border-gray-400 hover:bg-gray-50'}">
      <span class="truncate">{chosen?.label}</span>
      <Icon name="caret-down" size="xs" class="text-gray-400" />
    </button>
  {/snippet}
  <p class="px-2.5 pb-1 pt-1.5 text-xs font-medium text-gray-500">{title}</p>
  <ul role="listbox" aria-label={title} class="flex flex-col gap-0.5">
    {#each options as o}
      {@const on = (o.value || "") === current}
      <li role="option" aria-selected={on}>
        <a href={withQuery({ [param]: o.value || null })} class="flex items-center justify-between gap-2 rounded-md px-2.5 py-1.5 text-sm hover:bg-gray-100 {on ? 'font-medium text-gray-900' : 'text-gray-700'}">
          <span class="truncate">{o.label}</span>
          {#if on}<Icon name="check" class="text-accent-600" />{/if}
        </a>
      </li>
    {/each}
  </ul>
</Popover>
