<script>
  // The admin bar across the top (admin.css .admin-bar): the site, "+ New",
  // search, the theme, and the signed-in person's menu.
  import Icon from "../components/Icon.svelte";
  import Popover from "../components/Popover.svelte";
  import MenuItem from "../components/MenuItem.svelte";
  import { session } from "../session.svelte.js";
  import { site } from "../site.svelte.js";
  import { del } from "../api.js";
  let { onsearch, ondrawer } = $props();

  const newItems = $derived([
    ["Page", "#/pages/new", "pages:write"],
    ["Collection", "#/collections/new", "collections:write"],
    ["Global", "#/globals/new", "globals:write"],
    ["Block type", "#/blocks/new", "block_types:write"],
    ...site.collections.slice(0, 12).map((c) => [`Entry in ${c.name}`, `#/collections/${c.slug}/new`, "entries:write"]),
  ].filter(([, , cap]) => session.can(cap)));

  let theme = $state(document.documentElement.dataset.theme || "");
  function cycleTheme() {
    const order = ["", "light", "dark"];
    theme = order[(order.indexOf(theme) + 1) % 3];
    if (theme) document.documentElement.dataset.theme = theme; else delete document.documentElement.dataset.theme;
    try { theme ? localStorage.setItem("lp-theme", theme) : localStorage.removeItem("lp-theme"); } catch {}
  }
  const themeIcon = $derived(theme === "dark" ? "moon" : theme === "light" ? "sun" : "monitor");
  const themeLabel = $derived(theme === "dark" ? "Dark" : theme === "light" ? "Light" : "Same as the system");
  let newOpen = $state(false), siteOpen = $state(false), meOpen = $state(false);

  async function signOut() {
    await del("/session").catch(() => {});
    session.signedOut();
    location.hash = "#/";
  }
  const first = $derived((session.me?.user?.name || "").split(" ")[0] || session.me?.user?.email);
  const item = "flex h-full items-center gap-2 rounded-md px-2.5 whitespace-nowrap hover:bg-gray-100";
</script>

<header class="fixed inset-x-0 top-0 z-[21] flex h-12 items-stretch gap-1 border-b border-gray-200 bg-gray-50 p-2 text-sm leading-5 text-gray-900">
  <button type="button" class="{item} text-gray-600 hover:text-gray-900 md:hidden" onclick={ondrawer} aria-controls="admin-menu"><Icon name="menu" size="md" /><span class="sr-only">Menu</span></button>

  <Popover bind:open={siteOpen} class="flex">
    {#snippet trigger()}
      <a href="#/" class="{item} font-semibold" onmouseenter={() => (siteOpen = !!site.siteURL)} title="Dashboard">
        <span class="flex size-7 items-center justify-center rounded-md bg-accent-600 text-on-accent"><Icon name="home" /></span>
        <span class="hidden md:inline">{session.site || "Libre Publish"}</span>
      </a>
    {/snippet}
    {#if site.siteURL}<MenuItem href={site.siteURL} icon="external">View site</MenuItem>{/if}
  </Popover>

  {#if newItems.length}
    <Popover bind:open={newOpen} class="flex">
      {#snippet trigger({ toggle })}
        <button type="button" class="{item} text-gray-600 hover:text-gray-900" onclick={toggle} aria-haspopup="menu" aria-expanded={newOpen}>
          <Icon name="add" /><span class="hidden font-medium md:inline">New</span>
        </button>
      {/snippet}
      {#each newItems as [label, href]}<MenuItem {href}>{label}</MenuItem>{/each}
    </Popover>
  {/if}

  <div class="ml-auto flex items-center gap-1">
    <button type="button" onclick={onsearch} class="flex h-8 items-center gap-2 rounded-md px-2 text-gray-500 hover:bg-gray-100 hover:text-gray-900" title="Search everything (⌘K)">
      <Icon name="search" /><span class="hidden lg:inline">Search</span><kbd class="hidden lg:inline">⌘K</kbd>
    </button>
    <button type="button" onclick={cycleTheme} class="flex size-8 items-center justify-center rounded-md text-gray-600 hover:bg-gray-100 hover:text-gray-900" title="Theme: {themeLabel}">
      <Icon name={themeIcon} /><span class="sr-only">Theme: {themeLabel}</span>
    </button>
    <Popover bind:open={meOpen} align="end" class="flex">
      {#snippet trigger({ toggle })}
        <button type="button" class="{item} text-gray-600 hover:text-gray-900" onclick={toggle} aria-haspopup="menu" aria-expanded={meOpen}>
          <span class="hidden md:inline">Howdy, {first}</span>
          <span class="flex size-7 items-center justify-center rounded-full bg-gray-100 text-gray-600"><Icon name="person" /></span>
        </button>
      {/snippet}
      <p class="mb-1 truncate border-b border-gray-100 px-3 pb-2 pt-1.5 text-xs text-gray-500">{session.me?.user?.email}</p>
      <MenuItem href="#/account" icon="person">Your account</MenuItem>
      {#if session.can("settings:read")}<MenuItem href="#/settings" icon="settings-outline">Settings</MenuItem>{/if}
      <MenuItem href="#/connect" icon="link">Connect a device</MenuItem>
      <MenuItem icon="logout" onclick={signOut}>Sign out</MenuItem>
    </Popover>
  </div>
</header>
