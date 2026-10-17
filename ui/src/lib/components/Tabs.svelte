<script>
  // shadcn's Tabs list on its own, for a bound value (the panels are the
  // caller's).
  import * as Tabs from "$lib/components/ui/tabs/index.js";
  let { tabs = [], value = $bindable(), class: klass = "" } = $props();
</script>

<Tabs.Root bind:value class={klass}>
  <Tabs.List>
    {#each tabs as t}
      <Tabs.Trigger value={typeof t === "object" ? t.value : t}>{typeof t === "object" ? t.label : t}</Tabs.Trigger>
    {/each}
  </Tabs.List>
</Tabs.Root>
