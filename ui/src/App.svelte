<script>
  // The admin: signed out, the public screens (sign in, first-run setup);
  // signed in, the admin bar and the sidebar around the routed screen.
  import { ModeWatcher } from "mode-watcher";
  import * as Sidebar from "$lib/components/ui/sidebar/index.js";
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
  import Notice from "./lib/components/Notice.svelte";
  import { maintenance } from "./lib/maintenance.svelte.js";
  import SignIn from "./routes/SignIn.svelte";
  import Setup from "./routes/Setup.svelte";
  import NotFound from "./routes/NotFound.svelte";
  import ForgotPassword from "./routes/ForgotPassword.svelte";
  import ResetPassword from "./routes/ResetPassword.svelte";
  import ConfirmEmail from "./routes/ConfirmEmail.svelte";
  // Screens a mailed link opens: there whether or not anyone is signed in.
  const publicScreens = { "/forgot-password": ForgotPassword, "/reset-password": ResetPassword, "/confirm-email": ConfirmEmail };

  let searching = $state(false);
  // The sidebar remembers being folded in a cookie (shadcn's Sidebar).
  const menuOpen = !document.cookie.split("; ").includes("sidebar_state=false");

  session.load();
  $effect(() => { if (session.me) site.refresh(); });
  const matched = $derived(router.match(routes));
  $effect(() => { router.path; window.scrollTo(0, 0); });
  $effect(() => { document.title = session.site ? `${session.site} · Libre Publish` : "Libre Publish"; });
</script>

<ModeWatcher />
{#if maintenance.on}
  <div class="fixed inset-x-0 top-0 z-[110] p-2"><Notice tone="warning" class="mx-auto max-w-2xl shadow-md">The site is being replaced by an imported backup. It's back in a moment; reload then.</Notice></div>
{/if}
{#if !session.ready}
  <div class="flex min-h-dvh items-center justify-center"><Spinner /></div>
{:else if publicScreens[router.path] && (router.path !== "/forgot-password" || !session.me)}
  {@const Screen = publicScreens[router.path]}
  {#key router.path + router.query.toString()}<Screen />{/key}
{:else if !session.me}
  {#if session.needsSetup}<Setup />{:else}<SignIn />{/if}
{:else}
  <a href="#main" class="bg-background fixed left-2 top-2 z-[100] -translate-y-[200%] rounded-md px-3 py-2 text-sm font-medium shadow-md focus:translate-y-0">Skip to main content</a>
  <Sidebar.Provider open={menuOpen} class="pt-12">
    <AdminBar onsearch={() => (searching = true)} />
    <AdminMenu />
    <Sidebar.Inset class="min-w-0 px-[clamp(1rem,3vw,2rem)] pb-12 pt-6">
      <main id="main" class="mx-auto flex w-full max-w-[80rem] flex-col gap-4">
        {#key router.path + "?" + router.query.toString()}
          {#if matched}
            <matched.component params={matched.params} />
          {:else}
            <NotFound />
          {/if}
        {/key}
      </main>
    </Sidebar.Inset>
  </Sidebar.Provider>
  <GlobalSearch bind:open={searching} />
{/if}
<Toasts />
<ConfirmHost />
