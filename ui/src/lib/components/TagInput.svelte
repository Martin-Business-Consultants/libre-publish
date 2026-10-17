<script>
  // A list of short strings as chips: type and press Enter or comma to add,
  // Backspace on an empty input to take the last off.
  import Icon from "./Icon.svelte";
  let { value = $bindable([]), placeholder = "Add and press Enter", id = undefined, invalid = false } = $props();
  let draft = $state("");
  const list = $derived(Array.isArray(value) ? value : []);
  function add() {
    const v = draft.trim().replace(/,$/, "").trim();
    if (v && !list.includes(v)) value = [...list, v];
    draft = "";
  }
  function key(e) {
    if (e.key === "Enter" || e.key === ",") { e.preventDefault(); add(); }
    else if (e.key === "Backspace" && !draft && list.length) value = list.slice(0, -1);
  }
</script>

<div class="flex min-h-8 w-full flex-wrap items-center gap-1 rounded-md border bg-surface px-1.5 py-0.5 focus-within:border-gray-900 {invalid ? 'border-red-500' : 'border-gray-300 hover:border-gray-400'}">
  {#each list as v, i (v)}
    <span class="inline-flex items-center gap-1 rounded-sm bg-gray-100 py-0.5 pl-1.5 pr-0.5 text-xs font-medium text-gray-800">
      {v}
      <button type="button" class="rounded-sm p-0.5 text-gray-500 hover:bg-gray-200 hover:text-gray-900" onclick={() => (value = list.filter((_, j) => j !== i))} aria-label="Remove {v}"><Icon name="close" size="xs" /></button>
    </span>
  {/each}
  <input {id} bind:value={draft} onkeydown={key} onblur={add} class="min-w-24 flex-1 border-0 bg-transparent px-1 py-1 text-sm outline-none placeholder:text-gray-400" placeholder={list.length ? "" : placeholder} />
</div>
