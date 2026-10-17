<script>
  // The admin menu down the left (admin.css .admin-menu): groups of items,
  // the current one filled with its submenu open, the others' submenus
  // flying out on hover or focus. Folds to icons; on a narrow screen it's a
  // drawer the admin bar's menu button opens.
  import Icon from "../components/Icon.svelte";
  import { adminMenu } from "../menu.js";
  import { session } from "../session.svelte.js";
  import { site } from "../site.svelte.js";
  import { router } from "../router.svelte.js";
  let { drawer = $bindable(false), folded = $bindable(false) } = $props();

  const groups = $derived(
    adminMenu(site.collections)
      .map(([g, items]) => [g, items.filter((i) => !i.cap || session.can(i.cap)).map((i) => ({ ...i, submenu: (i.submenu || []).filter((s) => !s.cap || session.can(s.cap)) }))])
      .filter(([, items]) => items.length),
  );
  const path = $derived(router.path);
  const isCurrent = (i) => path === i.href || path.startsWith(i.href + "/") || (i.submenu || []).some((s) => s.href.split("?")[0] === path || path.startsWith(s.href.split("?")[0] + "/"));
  const subCurrent = (s) => {
    const h = s.href.split("?")[0];
    return path === h || (h !== "/pages" && h !== "/collections" && h !== "/settings" && path.startsWith(h + "/"));
  };
  function toggleFold() {
    folded = !folded;
    if (folded) document.documentElement.dataset.menu = "folded"; else delete document.documentElement.dataset.menu;
    try { localStorage.setItem("lp-menu", folded ? "folded" : "open"); } catch {}
  }
</script>

<nav
  id="admin-menu"
  aria-label="Admin menu"
  class="fixed bottom-0 left-0 top-12 z-20 flex flex-col border-r border-gray-200 bg-gray-50 text-sm leading-5 transition-transform
    max-md:w-[min(15rem,85vw)] max-md:overflow-y-auto {drawer ? 'max-md:translate-x-0 max-md:shadow-overlay' : 'max-md:-translate-x-full'}
    {folded ? 'md:w-16' : 'md:w-60'}"
>
  <ul class="flex shrink-0 grow flex-col gap-0.5 px-3 py-4">
    {#each groups as [group, items], gi}
      {#if gi > 0}<li class="mx-2.5 my-3 border-t border-gray-200" aria-hidden="true"></li>{/if}
      {#each items as i (i.id)}
        {@const current = isCurrent(i)}
        <li class="group/item relative">
          <a
            href={"#" + i.href}
            onclick={() => (drawer = false)}
            class="flex items-center gap-3 rounded-md px-2.5 py-2 font-medium {current ? 'bg-accent-50 text-accent-700' : 'text-gray-600 group-hover/item:bg-gray-100 group-hover/item:text-gray-900 group-focus-within/item:bg-gray-100'} {folded ? 'md:justify-center' : ''}"
            aria-current={current && !(i.submenu || []).some(subCurrent) ? "page" : undefined}
            title={folded ? i.label : undefined}
          >
            <Icon name={i.icon} size="md" class={current ? "text-accent-600" : "text-gray-400"} />
            <span class="truncate {folded ? 'md:hidden' : ''}">{i.label}</span>
            {#if i.badge === "reviews" && site.pendingReviews}
              <span class="ml-auto rounded-full bg-red-600 px-1.5 text-[11px] font-semibold leading-4 text-white {folded ? 'md:absolute md:right-1 md:top-1' : ''}">{site.pendingReviews}</span>
            {/if}
          </a>
          {#if i.submenu.length}
            <ul
              aria-label={i.label}
              class="{current && !folded ? 'block py-1' : 'hidden'}
                md:group-hover/item:block md:group-focus-within/item:block
                {current && !folded ? '' : 'md:absolute md:left-[calc(100%-0.5rem)] md:top-0 md:z-10 md:min-w-52 md:rounded-xl md:border md:border-gray-200 md:bg-surface md:p-1.5 md:shadow-overlay'}"
            >
              {#if !current || folded}<li class="hidden px-2.5 pb-1 pt-0.5 text-xs font-semibold uppercase tracking-wide text-gray-500 md:block">{i.label}</li>{/if}
              {#each i.submenu as s (s.href)}
                {@const on = subCurrent(s)}
                <li>
                  <a href={"#" + s.href} onclick={() => (drawer = false)}
                    class="flex items-center gap-2 rounded-md py-1.5 pr-2.5 {current && !folded ? 'pl-11' : 'pl-2.5'} {on ? 'font-medium text-accent-700' : 'text-gray-500 hover:bg-gray-100 hover:text-gray-900'}"
                    aria-current={on ? "page" : undefined}>
                    {#if s.icon}<Icon name={s.icon} class="text-gray-400" />{/if}<span class="truncate">{s.label}</span>
                  </a>
                </li>
              {/each}
            </ul>
          {/if}
        </li>
      {/each}
    {/each}
  </ul>
  <button type="button" onclick={toggleFold} aria-pressed={folded}
    class="mt-auto hidden items-center gap-3 border-t border-gray-200 py-3 text-left text-gray-500 hover:bg-gray-100 hover:text-gray-900 md:flex {folded ? 'justify-center px-0' : 'px-5'}">
    <Icon name="collapse-menu" size="md" class={folded ? "-scale-x-100" : ""} />
    <span class={folded ? "hidden" : ""}>Collapse menu</span>
  </button>
</nav>
{#if drawer}<button type="button" class="fixed inset-0 top-12 z-[19] bg-black/40 md:hidden" onclick={() => (drawer = false)} aria-label="Close the menu"></button>{/if}
