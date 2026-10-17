<script>
  // A labelled field (forms.css .field): the label (with a required mark and
  // a note), the control, help under it, and the API's errors for it. The
  // control is rendered with the id the label points at:
  //   <Field label="Title" required>{#snippet children(id)}<Input {id} … />{/snippet}</Field>
  let { label = "", required = false, note = "", help = "", error = null, id = undefined, class: klass = "", children, labelHidden = false } = $props();
  const uid = $props.id();
  const fid = $derived(id || `f-${uid}`);
  const messages = $derived(error == null ? [] : Array.isArray(error) ? error : [error]);
</script>

<div class="flex min-w-0 flex-col gap-1.5 {klass}">
  {#if label}
    <label for={fid} class="block text-sm font-semibold leading-5 text-gray-900 {labelHidden ? 'sr-only' : ''}">
      {label}{#if required}<span class="text-red-600" aria-hidden="true"> *</span>{/if}
      {#if note}<span class="ml-1 text-xs font-normal text-gray-500">{note}</span>{/if}
    </label>
  {/if}
  {@render children?.(fid, messages.length > 0)}
  {#if help}<p class="text-xs leading-4 text-gray-500">{help}</p>{/if}
  {#each messages as m}<p class="text-xs leading-4 text-red-600" role="alert">{m}</p>{/each}
</div>
