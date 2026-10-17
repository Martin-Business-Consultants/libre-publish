<script>
  // A Markdown field: Write and Preview tabs (the preview is drawn here, a
  // small subset: headings, emphasis, links, lists, code, quotes).
  import Tabs from "./Tabs.svelte";
  import { markdown } from "../markdown.js";
  let { value = $bindable(""), rows = 8, id = undefined, invalid = false, placeholder = "" } = $props();
  let tab = $state("write");
</script>

<div class="flex flex-col gap-1.5">
  <Tabs tabs={[{ value: "write", label: "Write" }, { value: "preview", label: "Preview" }]} bind:value={tab} />
  {#if tab === "write"}
    <textarea {id} bind:value {rows} {placeholder} class="control font-mono text-[13px] leading-5" aria-invalid={invalid || undefined}></textarea>
  {:else}
    <div class="prose-admin min-h-24 rounded-md border border-gray-200 bg-gray-50 px-3 py-2 text-sm">
      {#if value?.trim()}{@html markdown(value)}{:else}<p class="text-gray-400">Nothing to preview.</p>{/if}
    </div>
  {/if}
</div>
