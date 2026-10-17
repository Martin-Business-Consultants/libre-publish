<script>
  // Lost password: an address in, a reset link mailed out. The answer is
  // the same whether or not the address has an account.
  import PublicLayout from "./PublicLayout.svelte";
  import Field from "../lib/components/Field.svelte";
  import Input from "../lib/components/Input.svelte";
  import Button from "../lib/components/Button.svelte";
  import Notice from "../lib/components/Notice.svelte";
  import { post } from "../lib/api.js";
  import { toastError } from "../lib/toast.svelte.js";
  let email = $state(""), sent = $state(""), busy = $state(false);
  async function submit(e) {
    e.preventDefault();
    busy = true;
    try { sent = (await post("/password/forgot", { email }, { quiet: true })).message; } catch (err) { toastError(err); }
    busy = false;
  }
</script>

<PublicLayout>
  <form class="flex flex-col gap-5" onsubmit={submit}>
    <div>
      <h1 class="text-xl font-semibold tracking-tight">Forgot your password?</h1>
      <p class="text-muted-foreground mt-1 text-sm">Enter your account's email address and we'll send a link to choose a new one.</p>
    </div>
    {#if sent}
      <Notice tone="success">{sent}</Notice>
      <a href="#/" class="text-primary text-sm hover:underline">← Back to sign in</a>
    {:else}
      <Field label="Email">{#snippet children(id)}<Input {id} type="email" bind:value={email} required autocomplete="username" autofocus />{/snippet}</Field>
      <Button type="submit" variant="primary" block loading={busy}>Send the link</Button>
      <a href="#/" class="text-muted-foreground hover:text-foreground text-center text-sm">Back to sign in</a>
    {/if}
  </form>
</PublicLayout>
