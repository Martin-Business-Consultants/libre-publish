<script>
  // A list's "Bulk actions" select and Apply, as WordPress lays it out. The
  // chosen action runs on the ticked rows; a destructive one asks first.
  import Button from "./Button.svelte";
  import { confirm } from "../confirm.svelte.js";
  let { actions = [], count = 0, noun = "item", onapply } = $props();
  let choice = $state("");
  let busy = $state(false);
  async function apply() {
    const action = actions.find((a) => a.value === choice);
    if (!action || !count) return;
    if (action.confirm && !(await confirm({ title: `${action.label} ${count} ${count === 1 ? noun : noun + "s"}?`, message: action.confirm, confirmLabel: action.label, destructive: action.destructive }))) return;
    busy = true;
    try { await onapply(choice); choice = ""; } finally { busy = false; }
  }
</script>

<div class="flex items-center gap-2">
  <label class="sr-only" for="bulk-choice">Bulk actions</label>
  <select id="bulk-choice" class="control w-44" bind:value={choice}>
    <option value="">Bulk actions</option>
    {#each actions as a}<option value={a.value}>{a.label}</option>{/each}
  </select>
  <Button onclick={apply} disabled={!choice || !count} loading={busy}>Apply</Button>
  {#if count}<span class="text-xs text-gray-500">{count} selected</span>{/if}
</div>
