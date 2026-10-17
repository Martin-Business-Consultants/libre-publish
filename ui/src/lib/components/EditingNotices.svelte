<script>
  // What an editor says about editing together (lib/editing.svelte.js):
  // someone else has it open (take over, or go back); someone took it over
  // from you (what you typed is kept); an autosave newer than what's saved
  // (restore it, or let it go).
  import * as AlertDialog from "$lib/components/ui/alert-dialog/index.js";
  import Notice from "./Notice.svelte";
  import Button from "./Button.svelte";
  import Time from "./Time.svelte";
  let { editing, noun = "page", back, onrestore } = $props();
</script>

<AlertDialog.Root open={editing.state === "locked"}>
  <AlertDialog.Content>
    <AlertDialog.Header>
      <AlertDialog.Title>This {noun} is being edited</AlertDialog.Title>
      <AlertDialog.Description>
        <strong>{editing.holder?.user_name}</strong> has it open (since <Time value={editing.holder?.since} />). If you take over, they can't save
        any more; what they've typed is kept for them as an autosave.
      </AlertDialog.Description>
    </AlertDialog.Header>
    <AlertDialog.Footer>
      <AlertDialog.Cancel onclick={() => (location.hash = back)}>Go back</AlertDialog.Cancel>
      <AlertDialog.Action onclick={() => editing.takeOver()}>Take over</AlertDialog.Action>
    </AlertDialog.Footer>
  </AlertDialog.Content>
</AlertDialog.Root>

<AlertDialog.Root open={editing.state === "lost"}>
  <AlertDialog.Content>
    <AlertDialog.Header>
      <AlertDialog.Title>{editing.holder?.user_name} took over</AlertDialog.Title>
      <AlertDialog.Description>
        They're editing this {noun} now, so you can't save. What you'd typed is kept as your autosave: open the {noun} again once they're done to get it back.
      </AlertDialog.Description>
    </AlertDialog.Header>
    <AlertDialog.Footer>
      <AlertDialog.Action onclick={() => (location.hash = back)}>Back to the list</AlertDialog.Action>
    </AlertDialog.Footer>
  </AlertDialog.Content>
</AlertDialog.Root>

{#if editing.offer}
  <Notice tone="warning">
    <div class="flex flex-wrap items-center justify-between gap-2">
      <span>There's an autosave from <Time value={editing.offer.updated_at} />, newer than what's saved.</span>
      <span class="flex gap-2">
        <Button size="sm" onclick={() => editing.discard()}>Discard it</Button>
        <Button size="sm" variant="primary" onclick={() => { onrestore(editing.offer.data); editing.offer = null; }}>Restore it</Button>
      </span>
    </div>
  </Notice>
{/if}
