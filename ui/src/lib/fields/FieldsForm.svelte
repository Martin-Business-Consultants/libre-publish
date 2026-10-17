<script>
  // A form drawn from field definitions (the field DSL: string, text,
  // markdown, code, integer, boolean, select, url, datetime, link, asset,
  // record_ref(s), repeater, group, blocks, string_list), writing into
  // `data`. `errors` are the API's, keyed by path ("frontmatter.summary").
  import FieldControl from "./FieldControl.svelte";
  let { fields = [], data, path = "", errors = {}, gap = "gap-5" } = $props();
</script>

<div class="flex flex-col {gap}">
  {#each fields as f (f.name)}
    <FieldControl field={f} {data} path={path ? `${path}.${f.name}` : f.name} {errors} />
  {/each}
</div>
