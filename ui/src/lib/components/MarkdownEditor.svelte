<script>
  // A Markdown field, edited as rich text (TiptapEditor) and kept as
  // Markdown, which is what's stored. The Markdown tab shows and edits the
  // source itself.
  import TiptapEditor from "./TiptapEditor.svelte";
  import Tabs from "./Tabs.svelte";
  import Textarea from "./Textarea.svelte";

  let { value = $bindable(""), rows = 8, id = undefined, invalid = false, placeholder = "" } = $props();
  let tab = $state("write");
</script>

<div class="flex flex-col gap-1.5">
  <Tabs tabs={[{ value: "write", label: "Write" }, { value: "markdown", label: "Markdown" }]} bind:value={tab} />
  <div hidden={tab !== "write"}><TiptapEditor bind:value format="markdown" active={tab === "write"} {id} {invalid} {placeholder} /></div>
  {#if tab === "markdown"}
    <Textarea bind:value {rows} {placeholder} {invalid} mono aria-label="Markdown source" class="min-h-40 text-[13px]" />
  {/if}
</div>
