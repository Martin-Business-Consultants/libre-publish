<script>
  // WordPress's Publish box (content_form/_publish_box): Save Draft; the
  // status and the schedule, each with an Edit that opens in place; Move to
  // Trash and the one primary action. Without the publish capability there's
  // no primary action, and a note says what happens instead.
  import Button from "../components/Button.svelte";
  import Icon from "../components/Icon.svelte";
  import Select from "../components/Select.svelte";
  import Input from "../components/Input.svelte";
  import Notice from "../components/Notice.svelte";
  import { dateTime, humanize } from "../format.js";

  let { record, statusful = true, canPublish, isNew = false, saving = false, onsave, ontrash = null, statuses = ["draft", "published", "archived"] } = $props();
  let editStatus = $state(false), editSchedule = $state(false);
  const status = $derived(record.status || "draft");
  const live = $derived(!isNew && (statusful ? status === "published" : true));
  const scheduled = $derived(record.publish_at && new Date(record.publish_at) > new Date() && status !== "published");
  const primary = $derived.by(() => {
    if (!canPublish) return null;
    if (!statusful) return ["Update", null];
    if (status === "published") return ["Update", "published"];
    if (record.publish_at && new Date(record.publish_at) > new Date()) return ["Schedule", null];
    return ["Publish", "published"];
  });
  const toLocal = (iso) => {
    const d = new Date(iso); if (!iso || isNaN(d)) return "";
    const p = (n) => String(n).padStart(2, "0");
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`;
  };
</script>

<section class="rounded-xl border border-gray-200 bg-surface">
  <h2 class="border-b border-gray-200 px-5 py-3.5 text-base font-semibold text-gray-900">Publish</h2>
  {#if statusful && status === "draft"}
    <div class="px-5 pt-4"><Button size="sm" loading={saving} onclick={() => onsave("draft")}>Save Draft</Button></div>
  {/if}
  <div class="flex flex-col gap-3 px-5 py-4 text-sm text-gray-700">
    {#if statusful}
      <div class="flex items-start gap-2">
        <Icon name="pinned" class="mt-0.5 text-gray-400" />
        <div class="flex-1">
          Status: <strong class="font-semibold text-gray-900">{humanize(status)}</strong>
          <button type="button" class="ml-1 font-medium text-accent-600 underline decoration-accent-600/40 underline-offset-2 hover:text-accent-700" onclick={() => (editStatus = !editStatus)}>{editStatus ? "Done" : "Edit"}</button>
          {#if editStatus}<div class="mt-2"><Select options={statuses.map((s) => ({ value: s, label: humanize(s) }))} bind:value={record.status} aria-label="Status" /></div>{/if}
        </div>
      </div>
      <div class="flex items-start gap-2">
        <Icon name="history" class="mt-0.5 text-gray-400" />
        <div class="flex-1">
          {#if scheduled}Scheduled for <strong class="font-semibold text-gray-900">{dateTime(record.publish_at)}</strong>
          {:else if status === "published" && record.published_at}Published on <strong class="font-semibold text-gray-900">{dateTime(record.published_at)}</strong>
          {:else}Publish <strong class="font-semibold text-gray-900">immediately</strong>{/if}
          {#if status !== "published"}
            <button type="button" class="ml-1 font-medium text-accent-600 underline decoration-accent-600/40 underline-offset-2 hover:text-accent-700" onclick={() => (editSchedule = !editSchedule)}>{editSchedule ? "Done" : "Edit"}</button>
          {/if}
          {#if editSchedule}
            <div class="mt-2 flex flex-col gap-1">
              <Input type="datetime-local" value={toLocal(record.publish_at)} oninput={(e) => (record.publish_at = e.currentTarget.value ? new Date(e.currentTarget.value).toISOString() : null)} aria-label="Publish at" />
              <p class="text-xs text-gray-500">Leave it blank to publish when you press Publish.</p>
            </div>
          {/if}
        </div>
      </div>
    {/if}
    {#if !canPublish}
      <Notice tone="warning">
        {#if statusful && status === "draft" && !live}Your role can't publish. Save it as a draft, and someone who can publishes it.
        {:else if live}Your role can't change what's live: saving sends your changes to review, and the live version stays as it is until someone approves them.
        {:else}Your role can't publish this.{/if}
      </Notice>
    {/if}
  </div>
  <div class="flex items-center justify-between gap-2 rounded-b-xl border-t border-gray-200 bg-gray-50 px-5 py-3">
    {#if ontrash}<button type="button" class="text-sm font-medium text-red-600 hover:text-red-700 hover:underline" onclick={ontrash}>Move to Trash</button>{:else}<span></span>{/if}
    {#if primary}
      <Button variant="primary" loading={saving} onclick={() => onsave(primary[1])}>{primary[0]}</Button>
    {:else if !statusful || status !== "draft"}
      <Button variant="primary" loading={saving} onclick={() => onsave(null)}>{live ? "Propose changes" : "Save"}</Button>
    {/if}
  </div>
</section>
