<script>
  // A quick filter: a select-like button showing the choice, opening a menu
  // of the others. Each choice is a link that swaps one query parameter.
  import Popover from "./Popover.svelte";
  import Icon from "./Icon.svelte";
  import { buttonVariants } from "$lib/components/ui/button/index.js";
  import { router, withQuery } from "../router.svelte.js";
  let { title, param, options = [] } = $props();
  const current = $derived(router.query.get(param) || "");
  const chosen = $derived(options.find((o) => (o.value || "") === current) || options[0]);
  let open = $state(false);
</script>

<Popover bind:open width="w-56">
  {#snippet trigger({ props })}
    <button type="button" {...props} {title} class="{buttonVariants({ variant: current ? 'secondary' : 'outline' })} max-w-80">
      <span class="truncate">{chosen?.label}</span>
      <Icon name="caret-down" class="text-muted-foreground" />
    </button>
  {/snippet}
  <p class="text-muted-foreground px-2 pb-1 pt-1.5 text-xs font-medium">{title}</p>
  <ul role="listbox" aria-label={title} class="flex flex-col">
    {#each options as o}
      {@const on = (o.value || "") === current}
      <li role="option" aria-selected={on}>
        <a href={withQuery({ [param]: o.value || null })} class="hover:bg-accent flex items-center justify-between gap-2 rounded-sm px-2 py-1.5 text-sm {on ? 'font-medium' : ''}">
          <span class="truncate">{o.label}</span>
          {#if on}<Icon name="check" />{/if}
        </a>
      </li>
    {/each}
  </ul>
</Popover>
