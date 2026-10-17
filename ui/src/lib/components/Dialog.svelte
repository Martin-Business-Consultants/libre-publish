<script>
  // A dialog (dialog.css): a native <dialog>, modal, with the admin's fade
  // and scale; `sheet` slides in from the right instead. Escape and a click
  // on the backdrop close it.
  import Button from "./Button.svelte";
  let { open = $bindable(false), title = "", size = "md", sheet = false, children, actions = undefined, onclose = undefined } = $props();
  let el = $state();
  $effect(() => {
    if (!el) return;
    if (open && !el.open) el.showModal();
    if (!open && el.open) el.close();
  });
  const widths = { sm: "w-[28rem]", md: "w-[36rem]", lg: "w-[48rem]", xl: "w-[64rem]" };
</script>

<dialog
  bind:this={el}
  class="flex-col gap-4 border border-gray-200 bg-surface text-left text-gray-900 shadow-overlay backdrop:bg-black/40 backdrop:animate-fade-in open:flex
    {sheet
      ? `m-0 ml-auto h-dvh max-h-dvh max-w-[100vw] animate-slide-in rounded-none border-y-0 border-r-0 p-6 ${widths[size] || widths.md}`
      : `m-auto max-h-[calc(100dvh-2rem)] max-w-[calc(100vw-2rem)] animate-pop-in overflow-y-auto rounded-xl p-6 ${widths[size]}`}"
  onclose={() => { open = false; onclose?.(); }}
  onclick={(e) => { if (e.target === el) open = false; }}
>
  {#if open}
    {#if title}
      <header class="flex shrink-0 items-start justify-between gap-3">
        <h2 class="text-lg font-semibold leading-7 text-gray-900">{title}</h2>
        <Button variant="plain" size="sm" iconOnly icon="close" title="Close" onclick={() => (open = false)} />
      </header>
    {/if}
    <div class="flex min-h-0 flex-1 flex-col gap-4 {sheet ? 'overflow-y-auto' : ''}">{@render children()}</div>
    {#if actions}<footer class="mt-auto flex flex-wrap items-center justify-end gap-2">{@render actions()}</footer>{/if}
  {/if}
</dialog>
