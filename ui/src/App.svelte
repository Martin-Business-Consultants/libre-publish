<script>
  // The admin: signed out, the public screens (sign in, first-run setup);
  // signed in, the admin bar and menu around the routed screen.
  import { session } from "./lib/session.svelte.js";
  import { site } from "./lib/site.svelte.js";
  import { router } from "./lib/router.svelte.js";
  import { routes } from "./routes.js";
  import AdminBar from "./lib/layout/AdminBar.svelte";
  import AdminMenu from "./lib/layout/AdminMenu.svelte";
  import GlobalSearch from "./lib/layout/GlobalSearch.svelte";
  import Toasts from "./lib/components/Toasts.svelte";
  import ConfirmHost from "./lib/components/ConfirmHost.svelte";
  import Spinner from "./lib/components/Spinner.svelte";
  import SignIn from "./routes/SignIn.svelte";
  import Setup from "./routes/Setup.svelte";
  import NotFound from "./routes/NotFound.svelte";

  let drawer = $state(false);
  let folded = $state(document.documentElement.dataset.menu === "folded");
  let searching = $state(false);

  session.load();
  $effect(() => { if (session.me) site.refresh(); });
  const matched = $derived(router.match(routes));
  $effect(() => { router.path; drawer = false; window.scrollTo(0, 0); });
  $effect(() => { document.title = session.site ? `${session.site} · Libre Publish` : "Libre Publish"; });
</script>

{#if !session.ready}
  <div class="flex min-h-dvh items-center justify-center"><Spinner /></div>
{:else if !session.me}
  {#if session.needsSetup}<Setup />{:else}<SignIn />{/if}
{:else}
  <a href="#main" class="fixed left-2 top-2 z-[100] -translate-y-[200%] rounded-md bg-surface px-3 py-2 text-sm font-semibold shadow-overlay focus:translate-y-0">Skip to main content</a>
  <AdminBar onsearch={() => (searching = true)} ondrawer={() => (drawer = !drawer)} />
  <AdminMenu bind:drawer bind:folded />
  <div class="isolate min-w-0 px-[clamp(1rem,3vw,2rem)] pb-12 pt-[4.5rem] {folded ? 'md:pl-[calc(4rem+clamp(1rem,3vw,2rem))]' : 'md:pl-[calc(15rem+clamp(1rem,3vw,2rem))]'}">
    <main id="main" class="mx-auto flex max-w-[80rem] flex-col gap-4">
      {#key router.path + "?" + router.query.toString()}
        {#if matched}
          <matched.component params={matched.params} />
        {:else}
          <NotFound />
        {/if}
      {/key}
    </main>
  </div>
  <GlobalSearch bind:open={searching} />
{/if}
<Toasts />
<ConfirmHost />
