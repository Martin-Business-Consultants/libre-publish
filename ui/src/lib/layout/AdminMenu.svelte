<script>
  // The admin menu down the left, shadcn's Sidebar: groups of items, the
  // current one marked with its submenu open; any other submenu opens from
  // its chevron. It folds to icons (the bar's toggle, or ⌘B); on a narrow
  // screen it's a sheet.
  import * as Sidebar from "$lib/components/ui/sidebar/index.js";
  import * as Collapsible from "$lib/components/ui/collapsible/index.js";
  import { useSidebar } from "$lib/components/ui/sidebar/context.svelte.js";
  import Icon from "../components/Icon.svelte";
  import { adminMenu } from "../menu.js";
  import { session } from "../session.svelte.js";
  import { site } from "../site.svelte.js";
  import { router } from "../router.svelte.js";
  import { pluginMenus } from "../plugins.svelte.js";

  const sidebar = useSidebar();
  const groups = $derived(
    adminMenu(site.collections, pluginMenus.list)
      .map(([g, items]) => [g, items.filter((i) => !i.cap || session.can(i.cap)).map((i) => ({ ...i, submenu: (i.submenu || []).filter((s) => !s.cap || session.can(s.cap)) }))])
      .filter(([, items]) => items.length),
  );
  const path = $derived(router.path);
  const isCurrent = (i) => (i.exact ? path === i.href : false) || (!i.exact && ((i.prefix && path.startsWith(i.prefix)) || path === i.href || path.startsWith(i.href + "/") || (i.submenu || []).some((s) => s.href.split("?")[0] === path || path.startsWith(s.href.split("?")[0] + "/"))));
  const subCurrent = (s) => {
    const h = s.href.split("?")[0];
    return path === h || (h !== "/pages" && h !== "/collections" && h !== "/settings" && path.startsWith(h + "/"));
  };
  const close = () => sidebar.setOpenMobile(false);
</script>

<Sidebar.Root collapsible="icon" class="top-12 h-[calc(100svh-3rem)]!">
  <Sidebar.Content>
    {#each groups as [group, items]}
      <Sidebar.Group>
        <Sidebar.GroupLabel>{group}</Sidebar.GroupLabel>
        <Sidebar.Menu>
          {#each items as i (i.id)}
            {@const current = isCurrent(i)}
            <Collapsible.Root open={current}>
              {#snippet child({ props })}
                <Sidebar.MenuItem {...props}>
                  <Sidebar.MenuButton isActive={current && !i.submenu.some(subCurrent)} tooltipContent={i.label}>
                    {#snippet child({ props })}
                      <a href={"#" + i.href} onclick={close} {...props}><Icon name={i.icon} /><span>{i.label}</span></a>
                    {/snippet}
                  </Sidebar.MenuButton>
                  {@const count = i.badge === "reviews" ? site.pendingReviews : i.badge?.startsWith("plugin:") ? pluginMenus.badges[i.badge.slice(7)] : 0}
                  {#if count}
                    <Sidebar.MenuBadge class="bg-destructive text-white">{count}</Sidebar.MenuBadge>
                  {:else if i.submenu.length}
                    <Collapsible.Trigger>
                      {#snippet child({ props })}
                        <Sidebar.MenuAction {...props} class="data-[state=open]:rotate-180">
                          <Icon name="caret-down" /><span class="sr-only">{i.label}: more</span>
                        </Sidebar.MenuAction>
                      {/snippet}
                    </Collapsible.Trigger>
                  {/if}
                  {#if i.submenu.length}
                    <Collapsible.Content>
                      <Sidebar.MenuSub>
                        {#each i.submenu as s (s.href)}
                          <Sidebar.MenuSubItem>
                            <Sidebar.MenuSubButton isActive={subCurrent(s)}>
                              {#snippet child({ props })}
                                <a href={"#" + s.href} onclick={close} {...props}>{#if s.icon}<Icon name={s.icon} />{/if}<span>{s.label}</span></a>
                              {/snippet}
                            </Sidebar.MenuSubButton>
                          </Sidebar.MenuSubItem>
                        {/each}
                      </Sidebar.MenuSub>
                    </Collapsible.Content>
                  {/if}
                </Sidebar.MenuItem>
              {/snippet}
            </Collapsible.Root>
          {/each}
        </Sidebar.Menu>
      </Sidebar.Group>
    {/each}
  </Sidebar.Content>
  <Sidebar.Rail />
</Sidebar.Root>
