<script>
  import Dialog from "./Dialog.svelte";
  import Button from "./Button.svelte";
  import { confirmState } from "../confirm.svelte.js";
  let open = $state(false);
  let c = $derived(confirmState.current);
  $effect(() => { open = !!c; });
  function finish(answer) {
    c?.resolve(answer);
    confirmState.current = null;
  }
</script>

<Dialog bind:open title={c?.title || ""} size="sm" onclose={() => { if (confirmState.current) finish(false); }}>
  {#if c?.message}<p class="text-sm text-gray-700">{c.message}</p>{/if}
  {#snippet actions()}
    <Button onclick={() => finish(false)}>Cancel</Button>
    <Button variant={c?.destructive ? "destructive" : "primary"} icon={c?.destructive ? "trash" : null} onclick={() => finish(true)}>{c?.confirmLabel}</Button>
  {/snippet}
</Dialog>
