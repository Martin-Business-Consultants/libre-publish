<script>
  // A list's search: it updates the ?s= of the address as you type (after a
  // pause), so the search is in the URL and the back button undoes it.
  import Icon from "./Icon.svelte";
  import { router, withQuery } from "../router.svelte.js";
  let { placeholder = "Search…", param = "s", label = "Search" } = $props();
  // svelte-ignore state_referenced_locally
  let value = $state(router.query.get(param) || "");
  let timer;
  function input() {
    clearTimeout(timer);
    timer = setTimeout(() => { location.replace(withQuery({ [param]: value.trim() || null })); }, 250);
  }
</script>

<div class="relative flex w-full items-center sm:w-64">
  <Icon name="search" class="pointer-events-none absolute left-2.5 text-gray-400" />
  <input type="search" class="control pl-8" bind:value oninput={input} {placeholder} aria-label={label} />
</div>
