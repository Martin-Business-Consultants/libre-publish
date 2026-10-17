<script>
  let { value = $bindable(""), invalid = false, mono = false, rows = 4, class: klass = "", ...rest } = $props();
</script>

<textarea bind:value {rows} class="control {mono ? 'font-mono text-xs leading-5' : ''} {klass}" aria-invalid={invalid || undefined} {...rest}></textarea>
