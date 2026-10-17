<script>
  import EmptyState from "../lib/components/EmptyState.svelte";
  import Button from "../lib/components/Button.svelte";
</script>

<EmptyState icon="search" title="Nothing here">
  That address isn't a screen in the admin.
  {#snippet actions()}<Button href="#/">Go to the dashboard</Button>{/snippet}
</EmptyState>
