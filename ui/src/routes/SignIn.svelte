<script>
  import PublicLayout from "./PublicLayout.svelte";
  import Field from "../lib/components/Field.svelte";
  import Input from "../lib/components/Input.svelte";
  import Button from "../lib/components/Button.svelte";
  import Notice from "../lib/components/Notice.svelte";
  import { post } from "../lib/api.js";
  import { session } from "../lib/session.svelte.js";
  let email = $state(""), password = $state(""), error = $state(""), busy = $state(false);
  async function submit(e) {
    e.preventDefault();
    busy = true; error = "";
    try { await post("/session", { email, password }, { quiet: true }); await session.load(); }
    catch (err) { error = err.message; }
    busy = false;
  }
</script>

<PublicLayout>
  <form class="flex flex-col gap-5" onsubmit={submit}>
    <div>
      <h1 class="text-xl font-semibold tracking-tight">Sign in</h1>
      <p class="mt-1 text-sm text-gray-500">to the admin.</p>
    </div>
    {#if error}<Notice tone="danger">{error}</Notice>{/if}
    <Field label="Email">{#snippet children(id)}<Input {id} type="email" bind:value={email} required autocomplete="username" autofocus />{/snippet}</Field>
    <Field label="Password">{#snippet children(id)}<Input {id} type="password" bind:value={password} required autocomplete="current-password" />{/snippet}</Field>
    <Button type="submit" variant="primary" block loading={busy}>Sign in</Button>
  </form>
</PublicLayout>
