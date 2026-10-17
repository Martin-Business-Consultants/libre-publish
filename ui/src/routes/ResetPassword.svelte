<script>
  // A new password from a mailed link; it signs you in.
  import PublicLayout from "./PublicLayout.svelte";
  import Field from "../lib/components/Field.svelte";
  import Input from "../lib/components/Input.svelte";
  import Button from "../lib/components/Button.svelte";
  import Notice from "../lib/components/Notice.svelte";
  import PasswordStrength from "../lib/components/PasswordStrength.svelte";
  import { post, ApiError } from "../lib/api.js";
  import { session } from "../lib/session.svelte.js";
  import { router } from "../lib/router.svelte.js";
  const token = router.query.get("token") || "";
  let password = $state(""), errors = $state({}), problem = $state(""), done = $state(""), busy = $state(false);
  async function submit(e) {
    e.preventDefault();
    busy = true; problem = ""; errors = {};
    try {
      const r = await post("/password/reset", { token, password }, { quiet: true });
      if (r.signed_in) { await session.load(); location.hash = "#/"; } else done = r.message;
    } catch (err) {
      if (err instanceof ApiError && err.status === 422) errors = err.errors;
      else problem = err.message;
    }
    busy = false;
  }
</script>

<PublicLayout>
  <form class="flex flex-col gap-5" onsubmit={submit}>
    <div>
      <h1 class="text-xl font-semibold tracking-tight">Choose a new password</h1>
      <p class="text-muted-foreground mt-1 text-sm">You'll be signed out everywhere else.</p>
    </div>
    {#if problem}<Notice tone="danger">{problem} <a href="#/forgot-password" class="underline">Send a new link</a></Notice>{/if}
    {#if done}
      <Notice tone="success">{done}</Notice>
      <a href="#/" class="text-primary text-sm hover:underline">Sign in</a>
    {:else if !token}
      <Notice tone="danger">This link is incomplete. <a href="#/forgot-password" class="underline">Ask for a new one</a>.</Notice>
    {:else}
      <Field label="New password" help="At least 10 characters." error={errors.password}>
        {#snippet children(id, invalid)}<Input {id} {invalid} type="password" bind:value={password} required minlength="10" autocomplete="new-password" autofocus />{/snippet}
      </Field>
      <PasswordStrength {password} />
      <Button type="submit" variant="primary" block loading={busy}>Save and sign in</Button>
    {/if}
  </form>
</PublicLayout>
