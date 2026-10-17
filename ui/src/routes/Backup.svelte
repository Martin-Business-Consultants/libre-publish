<script>
  import PageHeader from "../lib/components/PageHeader.svelte";
  import Panel from "../lib/components/Panel.svelte";
  import Button from "../lib/components/Button.svelte";
</script>

<PageHeader title="Backup" cli="cms backup > backup.tar.gz" />
<div class="max-w-2xl">
  <Panel>
    <div class="flex flex-col gap-4 p-6 text-sm text-foreground/80">
      <p>A backup is a <code class="rounded-sm bg-muted px-1 font-mono text-xs">.tar.gz</code> of a consistent copy of the database and every uploaded file: the whole site.</p>
      <p>To restore it, unpack it into an empty data directory and start <code class="rounded-sm bg-muted px-1 font-mono text-xs">librepublish serve --data</code> on it.</p>
      <div><Button variant="primary" href="/api/tools/backup" icon="download">Download a backup</Button></div>
    </div>
  </Panel>
</div>
