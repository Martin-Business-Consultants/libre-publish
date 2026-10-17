<script>
  // The media picker: the library as tiles, a search, and uploading right
  // here (drop files on it, or choose them).
  import Dialog from "../components/Dialog.svelte";
  import Input from "../components/Input.svelte";
  import Button from "../components/Button.svelte";
  import Icon from "../components/Icon.svelte";
  import Spinner from "../components/Spinner.svelte";
  import { get, post } from "../api.js";
  import { toastError } from "../toast.svelte.js";
  import { session } from "../session.svelte.js";
  let { open = $bindable(false), onpick, accept = "" } = $props();
  let assets = $state([]), q = $state(""), loading = $state(false), uploading = $state(0), dragging = $state(false);
  let fileInput = $state();
  let timer;
  async function load() {
    loading = true;
    try { assets = (await get(`/assets?per=60${q ? "&q=" + encodeURIComponent(q) : ""}${accept ? "&type=" + accept : ""}`)).assets; } catch (e) { toastError(e); }
    loading = false;
  }
  $effect(() => { if (open) load(); });
  async function upload(files) {
    for (const f of files) {
      uploading++;
      const fd = new FormData();
      fd.append("file", f);
      try { const r = await post("/assets", fd); assets = [r.asset, ...assets]; } catch (e) { toastError(e); }
      uploading--;
    }
  }
</script>

<Dialog bind:open title="Choose a file" size="xl">
  <div class="flex flex-wrap items-center gap-2">
    <div class="min-w-48 flex-1"><Input icon="search" placeholder="Search the library…" bind:value={q} oninput={() => { clearTimeout(timer); timer = setTimeout(load, 200); }} /></div>
    {#if session.can("assets:write")}
      <input type="file" multiple class="hidden" bind:this={fileInput} onchange={(e) => { upload([...e.currentTarget.files]); e.currentTarget.value = ""; }} />
      <Button variant="primary" icon="add" loading={uploading > 0} onclick={() => fileInput.click()}>Upload</Button>
    {/if}
  </div>
  <div
    class="relative min-h-64 rounded-lg {dragging ? 'outline-2 outline-dashed outline-ring' : ''}"
    role="region" aria-label="Library"
    ondragover={(e) => { e.preventDefault(); dragging = true; }}
    ondragleave={() => (dragging = false)}
    ondrop={(e) => { e.preventDefault(); dragging = false; upload([...e.dataTransfer.files]); }}
  >
    {#if loading && !assets.length}
      <div class="flex justify-center py-16"><Spinner /></div>
    {:else if !assets.length}
      <div class="flex flex-col items-center gap-2 py-16 text-sm text-muted-foreground"><Icon name="picture-add" size="xl" class="text-muted-foreground/60" />{q ? "Nothing matches." : "The library is empty. Drop files here to upload them."}</div>
    {:else}
      <ul class="grid grid-cols-2 gap-x-3 gap-y-4 sm:grid-cols-3 lg:grid-cols-5">
        {#each assets as a (a.id)}
          <li class="min-w-0">
            <button type="button" class="group flex w-full flex-col gap-1.5 rounded-lg text-left" onclick={() => { onpick(a); open = false; }}>
              <span class="flex aspect-square w-full items-center justify-center overflow-hidden rounded-lg border border-border bg-muted/50 text-muted-foreground group-hover:border-ring group-focus-visible:border-ring">
                {#if a.thumb_url}<img src={a.thumb_url} alt={a.alt || ""} loading="lazy" class="size-full object-cover" />{:else}<Icon name="document" size="xl" />{/if}
              </span>
              <span class="truncate px-0.5 text-xs font-medium text-foreground/80">{a.filename}</span>
            </button>
          </li>
        {/each}
      </ul>
    {/if}
  </div>
</Dialog>
