<script>
  // A list's search: it updates the ?s= of the address as you type (after a
  // pause), so the search is in the URL and the back button undoes it.
  import Input from "./Input.svelte";
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

<Input type="search" icon="search" class="w-full sm:w-64" bind:value oninput={input} {placeholder} aria-label={label} />
