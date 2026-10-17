<script>
  // A repeater: a list of items, each a form of the same sub-fields, that
  // can be added, removed, dragged to reorder and folded.
  import FieldsForm from "./FieldsForm.svelte";
  import Button from "../components/Button.svelte";
  import Icon from "../components/Icon.svelte";
  import DragHandle from "../components/DragHandle.svelte";
  import { sortable, move } from "../sortable.js";
  let { field, items, path, errors = {} } = $props();
  const noun = $derived((field.label || field.name).replace(/s$/i, "").toLowerCase());
  const title = (item, i) => {
    const first = (field.of || []).find((s) => ["string", "text"].includes(s.type) && typeof item[s.name] === "string" && item[s.name]);
    return first ? item[first.name] : `${noun.replace(/^./, (c) => c.toUpperCase())} ${i + 1}`;
  };
</script>

<div class="flex flex-col gap-2" {@attach sortable(() => items)}>
  {#each items as item, i (item)}
    <details class="group bg-card rounded-lg border" open data-sortable-item>
      <summary class="flex items-center gap-2 py-1.5 pl-1.5 pr-1.5 group-open:border-b">
        <DragHandle onmove={(d) => move(items, i, i + d)} />
        <Icon name="caret-down" class="text-muted-foreground transition-transform group-[:not([open])]:-rotate-90" />
        <span class="min-w-0 flex-1 truncate text-sm font-medium text-foreground">{title(item, i)}</span>
        <Button variant="plain" size="sm" iconOnly icon="trash" title="Remove" class="hover:bg-destructive/10 hover:text-destructive" onclick={(e) => { e.preventDefault(); items.splice(i, 1); }} />
      </summary>
      <div class="p-4"><FieldsForm fields={field.of || []} data={item} path="{path}[{i}]" {errors} gap="gap-4" /></div>
    </details>
  {/each}
  <div><Button size="sm" icon="add" onclick={() => items.push({})}>Add {noun}</Button></div>
</div>
