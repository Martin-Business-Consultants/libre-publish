<script>
  // First run: the site's name and the first administrator.
  import PublicLayout from "./PublicLayout.svelte";
  import Field from "../lib/components/Field.svelte";
  import Input from "../lib/components/Input.svelte";
  import Button from "../lib/components/Button.svelte";
  import PasswordStrength from "../lib/components/PasswordStrength.svelte";
  import { post, ApiError } from "../lib/api.js";
  import { session } from "../lib/session.svelte.js";
  import { toastError } from "../lib/toast.svelte.js";
  let form = $state({ site: "", name: "", email: "", password: "" });
  let errors = $state({}), busy = $state(false);
  async function submit(e) {
    e.preventDefault();
    busy = true;
    try { await post("/setup", form, { quiet: true }); await session.load(); }
    catch (err) { if (err instanceof ApiError && err.status === 422) errors = err.errors; else toastError(err); }
    busy = false;
  }
</script>

<PublicLayout>
  <form class="flex flex-col gap-5" onsubmit={submit}>
    <div>
      <h1 class="text-xl font-semibold tracking-tight">Set up your CMS</h1>
      <p class="mt-1 text-sm text-muted-foreground">Name the site and make the first administrator. Everyone else can be added after.</p>
    </div>
    <Field label="Site name" error={errors.site}>{#snippet children(id)}<Input {id} bind:value={form.site} required autofocus placeholder="Old Mill" />{/snippet}</Field>
    <Field label="Your name" error={errors.name}>{#snippet children(id)}<Input {id} bind:value={form.name} required autocomplete="name" />{/snippet}</Field>
    <Field label="Email" error={errors.email}>{#snippet children(id)}<Input {id} type="email" bind:value={form.email} required autocomplete="email" />{/snippet}</Field>
    <Field label="Password" help="At least 10 characters." error={errors.password}>{#snippet children(id)}<Input {id} type="password" bind:value={form.password} required minlength="10" autocomplete="new-password" />{/snippet}</Field>
    <PasswordStrength password={form.password} />
    <Button type="submit" variant="primary" block loading={busy}>Create and sign in</Button>
  </form>
</PublicLayout>
