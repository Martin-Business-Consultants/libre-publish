<script>
  // Import a backup (this core's or the Rails core's), which replaces the
  // whole site: upload, read what staging found, then confirm. Applying
  // signs everyone out, so it ends at sign-in.
  import PageHeader from "../lib/components/PageHeader.svelte";
  import Panel from "../lib/components/Panel.svelte";
  import Button from "../lib/components/Button.svelte";
  import Field from "../lib/components/Field.svelte";
  import Input from "../lib/components/Input.svelte";
  import Textarea from "../lib/components/Textarea.svelte";
  import Notice from "../lib/components/Notice.svelte";
  import Spinner from "../lib/components/Spinner.svelte";
  import Badge from "../lib/components/Badge.svelte";
  import { del, post, ApiError } from "../lib/api.js";
  import { session } from "../lib/session.svelte.js";
  import { toastError } from "../lib/toast.svelte.js";
  import { bytes, dateTime, plural } from "../lib/format.js";

  const system = $derived(!!session.me?.system);

  // idle → uploading → checking → staged → applying → done
  let step = $state("idle");
  let progress = $state(0);
  let fileSize = $state(0);
  let report = $state(null);
  let uploadError = $state("");
  let secretKey = $state("");
  let confirmText = $state("");
  let errors = $state({});
  let input = $state(null);

  const confirmed = $derived(confirmText.trim() === "REPLACE");
  const plan = $derived(report?.secrets?.plan || { total: 0 });
  const tables = $derived(Object.entries(report?.tables || {}).sort((a, b) => b[1] - a[1]));

  // XHR rather than fetch, for the upload's progress.
  function upload(file) {
    uploadError = "";
    errors = {};
    report = null;
    fileSize = file.size;
    progress = 0;
    step = "uploading";
    const xhr = new XMLHttpRequest();
    xhr.open("POST", "/api/tools/import?filename=" + encodeURIComponent(file.name));
    xhr.setRequestHeader("X-CSRF-Token", session.csrf);
    xhr.setRequestHeader("Accept", "application/json");
    xhr.setRequestHeader("Content-Type", "application/gzip");
    xhr.upload.onprogress = (e) => {
      if (e.lengthComputable) progress = Math.round((e.loaded / e.total) * 100);
    };
    xhr.upload.onload = () => (step = "checking");
    xhr.onerror = () => { step = "idle"; uploadError = "The upload didn't go through: check the connection and try again."; };
    xhr.onload = () => {
      let body = {};
      try { body = JSON.parse(xhr.responseText || "{}"); } catch { body = { message: xhr.responseText }; }
      if (xhr.status === 401) { session.signedOut(); return; }
      if (xhr.status !== 201) {
        step = "idle";
        uploadError = body.message || `The CMS answered ${xhr.status}.`;
        return;
      }
      report = body.import;
      confirmText = "";
      step = "staged";
    };
    xhr.send(file);
  }

  async function discard() {
    if (report) {
      try { await del(`/tools/import/${report.id}`); } catch (e) { if (!(e instanceof ApiError && e.status === 404)) toastError(e); }
    }
    report = null;
    step = "idle";
  }

  async function apply() {
    errors = {};
    step = "applying";
    try {
      const r = await post(`/tools/import/${report.id}/apply`, { force: true, secret_key: secretKey.trim() });
      report = r.import;
      step = "done";
      setTimeout(() => { session.signedOut(); location.hash = "#/"; }, 6000);
    } catch (e) {
      step = "staged";
      if (e instanceof ApiError && e.status === 422 && e.errors.secret_key) errors = e.errors;
      else toastError(e);
    }
  }

  function signIn() {
    session.signedOut();
    location.hash = "#/";
  }
</script>

<PageHeader title="Import" cli="librepublish import backup.tar.gz" />
<div class="flex max-w-3xl flex-col gap-6">
  <Panel title="Import a backup">
    <div class="flex flex-col gap-4 p-6 text-sm">
      {#if !system}
        <p class="text-muted-foreground">Importing replaces the whole site, so only the Administrator role can.</p>
      {:else if step === "idle" || step === "uploading" || step === "checking"}
        <p class="text-foreground/80">A backup from this CMS or from the Rails core (its Tools › Backup, or a data directory backup) replaces <strong>everything here</strong>: pages, entries, files, people, settings. You'll see what's in it before anything changes.</p>
        {#if uploadError}<Notice tone="danger">{uploadError}</Notice>{/if}
        <input type="file" accept=".gz,.tgz,.tar,application/gzip,application/x-tar" class="hidden" bind:this={input}
          onchange={(e) => { if (e.currentTarget.files[0]) upload(e.currentTarget.files[0]); e.currentTarget.value = ""; }} />
        {#if step === "idle"}
          <div><Button icon="upload" onclick={() => input.click()}>Choose a backup…</Button></div>
        {:else}
          <div class="flex flex-col gap-2" aria-live="polite">
            <div class="flex items-center justify-between text-xs text-muted-foreground">
              <span>{step === "uploading" ? `Uploading ${bytes(fileSize)}…` : "Checking it: unpacking, migrating, verifying the files…"}</span>
              {#if step === "uploading"}<span>{progress}%</span>{:else}<Spinner />{/if}
            </div>
            <div class="h-2 overflow-hidden rounded-full bg-muted" role="progressbar" aria-valuemin="0" aria-valuemax="100" aria-valuenow={progress}>
              <div class="h-full bg-primary transition-[width]" style="width: {progress}%"></div>
            </div>
          </div>
        {/if}
      {:else if step === "done"}
        <Notice tone="success">The site was replaced by <strong>{report.source}</strong>. Everyone has been signed out, you too: sign in with an account from the imported site. The previous site is kept on the server in <code class="font-mono text-xs">{report.replaced_dir}</code>.</Notice>
        <div><Button variant="primary" onclick={signIn}>Sign in</Button></div>
      {:else if report}
        <div class="flex flex-wrap items-center gap-2">
          <Badge tone="info">{report.format_label}</Badge>
          <span class="font-medium">{report.source}</span>
          {#if report.manifest?.generated_at}<span class="text-muted-foreground">made {dateTime(report.manifest.generated_at)}{report.manifest.cms_version ? ` by ${report.manifest.cms_version}` : ""}</span>{/if}
          {#if report.manifest?.tenant}<span class="text-muted-foreground">tenant {report.manifest.tenant}</span>{/if}
        </div>

        <dl class="grid grid-cols-[max-content_1fr] gap-x-6 gap-y-2">
          <dt class="text-muted-foreground">Files</dt>
          <dd>{plural(report.blobs.total, "file")}: {report.blobs.copied} whole{#if report.blobs.missing}, <span class="text-destructive">{report.blobs.missing} missing</span>{/if}{#if report.blobs.mismatched}, <span class="text-destructive">{report.blobs.mismatched} not matching their checksum</span>{/if}</dd>
          {#if report.forms.forms || report.forms.submissions}
            <dt class="text-muted-foreground">Forms</dt>
            <dd>{plural(report.forms.forms, "form")}, {plural(report.forms.submissions, "submission")} and {plural(report.forms.emails, "email")} converted for the Forms plugin</dd>
          {/if}
          {#if plan.total}
            <dt class="text-muted-foreground">Secrets</dt>
            <dd>{plural(plan.total, "sealed value")}: {plan.kept} readable here, {plan.resealed} to re-seal{#if plan.cleared}, <span class="text-destructive">{plan.cleared} to clear</span>{/if}</dd>
          {/if}
          <dt class="text-muted-foreground">Schema</dt>
          <dd>version {report.schema_from}{report.schema_from !== report.schema_to ? `, migrated to ${report.schema_to}` : ""}</dd>
        </dl>

        {#if tables.length}
          <details class="rounded-md border px-3 py-2">
            <summary class="cursor-pointer text-muted-foreground">Records ({tables.length} tables)</summary>
            <ul class="mt-2 grid grid-cols-2 gap-x-6 gap-y-1 font-mono text-xs sm:grid-cols-3">
              {#each tables as [name, n]}<li class="flex justify-between gap-2"><span class="truncate">{name}</span><span>{n}</span></li>{/each}
            </ul>
          </details>
        {/if}

        {#if report.warnings?.length}
          <Notice tone="warning">
            <ul class="flex list-disc flex-col gap-1 pl-4">{#each report.warnings as w}<li>{w}</li>{/each}</ul>
          </Notice>
        {/if}
        {#if report.forms.not_carried?.length}
          <details class="rounded-md border px-3 py-2">
            <summary class="cursor-pointer text-muted-foreground">Not carried over from the Rails forms ({report.forms.not_carried.length})</summary>
            <ul class="mt-2 flex list-disc flex-col gap-1 pl-4 text-xs">{#each report.forms.not_carried as w}<li>{w}</li>{/each}</ul>
          </details>
        {/if}

        {#if plan.total > plan.kept}
          <Field label="The old install's secret key" note="optional" error={errors.secret_key}
            help={report.secrets.key_in_backup
              ? "The backup brought its key, so its secrets carry over. Paste another only if that one is wrong."
              : "Its data directory's secret.key, or the SECRET_KEY it ran with. Without it, the values above are cleared: tokens still sign in, but webhook secrets need rotating and the SMTP password entering again."}>
            {#snippet children(id, invalid)}<Textarea {id} {invalid} mono rows={2} bind:value={secretKey} autocomplete="off" spellcheck="false" />{/snippet}
          </Field>
        {/if}

        <Notice tone="danger">
          Importing <strong>replaces this whole site</strong> ({session.site || "this site"}): every page, entry, file, person and setting here is swapped for the backup's, and everyone is signed out, you included. The current site is kept on the server (in <code class="font-mono text-xs">replaced-&lt;time&gt;/</code> in the data directory) and can be put back by hand.
        </Notice>
        <Field label="Type REPLACE to confirm">
          {#snippet children(id)}<Input {id} bind:value={confirmText} autocomplete="off" class="max-w-xs" disabled={step === "applying"} />{/snippet}
        </Field>
        <div class="flex flex-wrap gap-2">
          <Button variant="destructive" disabled={!confirmed} loading={step === "applying"} onclick={apply}>Replace this site</Button>
          <Button variant="plain" disabled={step === "applying"} onclick={discard}>Discard</Button>
        </div>
        {#if step === "applying"}<p class="text-muted-foreground" aria-live="polite">Replacing the site. It answers "maintenance" until it's done.</p>{/if}
      {/if}
    </div>
  </Panel>
</div>
