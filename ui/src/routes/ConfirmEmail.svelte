<script>
  // A new email address, confirmed from the link sent to it.
  import PublicLayout from "./PublicLayout.svelte";
  import Notice from "../lib/components/Notice.svelte";
  import Spinner from "../lib/components/Spinner.svelte";
  import { post } from "../lib/api.js";
  import { session } from "../lib/session.svelte.js";
  import { router } from "../lib/router.svelte.js";
  let state = $state("working"), message = $state("");
  post("/email/confirm", { token: router.query.get("token") || "" }, { quiet: true })
    .then((r) => { state = "done"; message = r.message; if (session.me) session.me.user.email = r.email; })
    .catch((e) => { state = "failed"; message = e.message; });
</script>

<PublicLayout>
  <div class="flex flex-col gap-4">
    <h1 class="text-xl font-semibold tracking-tight">Confirm your email address</h1>
    {#if state === "working"}<div class="flex justify-center py-6"><Spinner /></div>
    {:else}<Notice tone={state === "done" ? "success" : "danger"}>{message}</Notice>{/if}
    <a href="#/{session.me ? 'account' : ''}" class="text-primary text-sm hover:underline">{session.me ? "Back to your account" : "Sign in"}</a>
  </div>
</PublicLayout>
