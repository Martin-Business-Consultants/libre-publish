<script>
  // The admin bar across the top: the menu toggle, the site, "+ New",
  // search, the theme, and the signed-in person's menu.
  import * as DropdownMenu from "$lib/components/ui/dropdown-menu/index.js";
  import { Button } from "$lib/components/ui/button/index.js";
  import { Separator } from "$lib/components/ui/separator/index.js";
  import { SidebarTrigger } from "$lib/components/ui/sidebar/index.js";
  import { userPrefersMode, setMode } from "mode-watcher";
  import Icon from "../components/Icon.svelte";
  import { session } from "../session.svelte.js";
  import { site } from "../site.svelte.js";
  import { del } from "../api.js";
  import { brand } from "../branding.svelte.js";
  let { onsearch } = $props();

  const newItems = $derived([
    ["Page", "#/pages/new", "pages:write"],
    ["Collection", "#/collections/new", "collections:write"],
    ["Global", "#/globals/new", "globals:write"],
    ["Block type", "#/blocks/new", "block_types:write"],
    ...site.collections.slice(0, 12).map((c) => [`Entry in ${c.name}`, `#/collections/${c.slug}/new`, "entries:write"]),
  ].filter(([, , cap]) => session.can(cap)));

  const themes = { system: ["monitor", "Same as the system"], light: ["sun", "Light"], dark: ["moon", "Dark"] };
  const theme = $derived(userPrefersMode.current || "system");
  function cycleTheme() { setMode({ system: "light", light: "dark", dark: "system" }[theme]); }

  async function signOut() {
    await del("/session").catch(() => {});
    session.signedOut();
    location.hash = "#/";
  }
  const first = $derived((session.me?.user?.name || "").split(" ")[0] || session.me?.user?.email);
</script>

<!-- Settings › Brand's top bar "Dark" keeps it dark in light mode too (a logo drawn for a dark ground). -->
<header class="bg-background text-foreground fixed inset-x-0 top-0 z-20 flex h-12 items-center gap-1 border-b px-2 {brand.current.top_bar === 'dark' ? 'dark' : ''}">
  <SidebarTrigger />
  <Separator orientation="vertical" class="mx-1 data-vertical:h-4 data-vertical:self-center" />
  <Button variant="ghost" size="sm" href="#/" class="font-semibold" title="Dashboard">
    <!-- The logo stands for the site's name; without one, the name does. -->
    {#if brand.current.logo}
      <img src={brand.current.logo.thumb} alt={session.site || "Libre Publish"} class="h-6 w-auto max-w-32 object-contain" />
    {:else}
      <Icon name="home" />
      <span class="hidden md:inline">{session.site || "Libre Publish"}</span>
    {/if}
  </Button>
  {#if site.siteURL}
    <Button variant="ghost" size="icon-sm" href={site.siteURL} title="View site"><Icon name="external" /><span class="sr-only">View site</span></Button>
  {/if}

  {#if newItems.length}
    <DropdownMenu.Root>
      <DropdownMenu.Trigger>
        {#snippet child({ props })}<Button variant="ghost" size="sm" {...props}><Icon name="add" /><span class="hidden md:inline">New</span></Button>{/snippet}
      </DropdownMenu.Trigger>
      <DropdownMenu.Content align="start" class="w-56">
        {#each newItems as [label, href]}
          <DropdownMenu.Item>{#snippet child({ props })}<a {href} {...props}>{label}</a>{/snippet}</DropdownMenu.Item>
        {/each}
      </DropdownMenu.Content>
    </DropdownMenu.Root>
  {/if}

  <div class="ml-auto flex items-center gap-1">
    <Button variant="ghost" size="sm" class="text-muted-foreground" onclick={onsearch} title="Search everything (⌘K)">
      <Icon name="search" /><span class="hidden lg:inline">Search</span><kbd class="hidden lg:inline-flex">⌘K</kbd>
    </Button>
    <Button variant="ghost" size="icon-sm" onclick={cycleTheme} title="Theme: {themes[theme][1]}">
      <Icon name={themes[theme][0]} /><span class="sr-only">Theme: {themes[theme][1]}</span>
    </Button>
    <DropdownMenu.Root>
      <DropdownMenu.Trigger>
        {#snippet child({ props })}
          <Button variant="ghost" size="sm" {...props}><span class="hidden md:inline">Howdy, {first}</span><Icon name="person" /></Button>
        {/snippet}
      </DropdownMenu.Trigger>
      <DropdownMenu.Content align="end" class="w-56">
        <DropdownMenu.Label class="text-muted-foreground truncate text-xs font-normal">{session.me?.user?.email}</DropdownMenu.Label>
        <DropdownMenu.Separator />
        <DropdownMenu.Item>{#snippet child({ props })}<a href="#/account" {...props}><Icon name="person" />Your account</a>{/snippet}</DropdownMenu.Item>
        {#if session.can("settings:read")}
          <DropdownMenu.Item>{#snippet child({ props })}<a href="#/settings" {...props}><Icon name="settings-outline" />Settings</a>{/snippet}</DropdownMenu.Item>
        {/if}
        <DropdownMenu.Item>{#snippet child({ props })}<a href="#/connect" {...props}><Icon name="link" />Connect a device</a>{/snippet}</DropdownMenu.Item>
        <DropdownMenu.Separator />
        <DropdownMenu.Item onSelect={signOut}><Icon name="logout" />Sign out</DropdownMenu.Item>
      </DropdownMenu.Content>
    </DropdownMenu.Root>
  </div>
</header>
