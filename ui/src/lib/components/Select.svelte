<script>
  // A native select in the admin's look. options: [{value, label}] or
  // strings; `placeholder` adds an empty first choice, which reads back as
  // null. Values match whatever their type (an id 3 or "3"), and the chosen
  // option's own value is what's bound.
  let { value = $bindable(""), options = [], placeholder = null, invalid = false, class: klass = "", onchange = undefined, ...rest } = $props();
  const opts = $derived(options.map((o) => (typeof o === "object" ? o : { value: o, label: o })));
  const current = $derived(value == null ? "" : String(value));
  function change(e) {
    const i = e.currentTarget.selectedIndex - (placeholder !== null ? 1 : 0);
    value = i < 0 ? (placeholder !== null ? null : "") : opts[i].value;
    onchange?.(e);
  }
</script>

<select class="control {klass}" aria-invalid={invalid || undefined} onchange={change} {...rest}>
  {#if placeholder !== null}<option value="" selected={current === ""}>{placeholder}</option>{/if}
  {#each opts as o}<option value={String(o.value)} selected={String(o.value) === current} disabled={o.disabled}>{o.label}</option>{/each}
</select>
