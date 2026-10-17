<script>
  // Flash messages, bottom right.
  import { toasts } from "../toast.svelte.js";
  import Icon from "./Icon.svelte";
  const icons = { success: "check-circle", danger: "close-circle", info: "help-circle" };
  const tones = { success: "text-green-600", danger: "text-red-600", info: "text-accent-600" };
</script>

<div class="pointer-events-none fixed bottom-4 right-4 z-50 flex w-[min(26rem,calc(100vw-2rem))] flex-col gap-2" aria-live="polite">
  {#each toasts.items as t (t.id)}
    <div class="pointer-events-auto flex animate-pop-in items-start gap-3 rounded-xl border border-gray-200 bg-surface px-4 py-3 text-sm text-gray-900 shadow-overlay" role={t.tone === "danger" ? "alert" : "status"}>
      <Icon name={icons[t.tone]} size="md" class={tones[t.tone]} />
      <p class="min-w-0 flex-1 break-words">{t.message}</p>
      <button type="button" class="text-gray-400 hover:text-gray-900" onclick={() => toasts.dismiss(t.id)} aria-label="Dismiss"><Icon name="close" /></button>
    </div>
  {/each}
</div>
