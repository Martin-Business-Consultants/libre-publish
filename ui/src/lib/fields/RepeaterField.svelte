<script>
  // A repeater: a list of items, each a form of the same sub-fields, that
  // can be added, removed, reordered and folded.
  import FieldsForm from "./FieldsForm.svelte";
  import Button from "../components/Button.svelte";
  import Icon from "../components/Icon.svelte";
  let { field, items, path, errors = {} } = $props();
  const noun = $derived((field.label || field.name).replace(/s$/i, "").toLowerCase());
  const title = (item, i) => {
    const first = (field.of || []).find((s) => ["string", "text"].includes(s.type) && typeof item[s.name] === "string" && item[s.name]);
    return first ? item[first.name] : `${noun.replace(/^./, (c) => c.toUpperCase())} ${i + 1}`;
  };
  function move(i, d) { const [x] = items.splice(i, 1); items.splice(i + d, 0, x); }
</script>

<div class="flex flex-col gap-2">
  {#each items as item, i (item)}
    <details class="group rounded-lg border border-gray-200 bg-surface" open>
      <summary class="flex items-center gap-2 py-1.5 pl-2 pr-1.5 group-open:border-b group-open:border-gray-200">
        <Icon name="caret-down" class="text-gray-400 transition-transform group-[:not([open])]:-rotate-90" />
        <span class="min-w-0 flex-1 truncate text-sm font-medium text-gray-900">{title(item, i)}</span>
        <Button variant="plain" size="sm" iconOnly icon="arrow-up" title="Move up" disabled={i === 0} onclick={(e) => { e.preventDefault(); move(i, -1); }} />
        <Button variant="plain" size="sm" iconOnly icon="arrow-up" class="rotate-180" title="Move down" disabled={i === items.length - 1} onclick={(e) => { e.preventDefault(); move(i, 1); }} />
        <Button variant="plain" size="sm" iconOnly icon="trash" title="Remove" class="hover:!bg-red-50 hover:!text-red-700" onclick={(e) => { e.preventDefault(); items.splice(i, 1); }} />
      </summary>
      <div class="p-4"><FieldsForm fields={field.of || []} data={item} path="{path}[{i}]" {errors} gap="gap-4" /></div>
    </details>
  {/each}
  <div><Button size="sm" icon="add" onclick={() => items.push({})}>Add {noun}</Button></div>
</div>
