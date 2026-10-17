<script>
  // The admin's button (buttons.css): default, primary, danger (red text),
  // destructive (red fill), plain (no border); sm; icon-only; a link when
  // given an href. While `loading`, it keeps its width and shows a spinner.
  import Icon from "./Icon.svelte";
  import Spinner from "./Spinner.svelte";

  let {
    variant = "default",
    size = "md",
    icon = null,
    iconOnly = false,
    href = null,
    type = "button",
    loading = false,
    disabled = false,
    block = false,
    title = undefined,
    class: klass = "",
    children,
    ...rest
  } = $props();

  const variants = {
    default: "bg-surface border-gray-300 text-gray-900 hover:enabled:bg-gray-50 hover:enabled:border-gray-400 [a&]:hover:bg-gray-50 [a&]:hover:border-gray-400",
    primary: "bg-accent-600 border-accent-600 text-on-accent hover:enabled:bg-accent-700 hover:enabled:border-accent-700 [a&]:hover:bg-accent-700",
    danger: "bg-surface border-gray-300 text-red-600 hover:enabled:bg-red-50",
    destructive: "bg-red-600 border-red-600 text-white hover:enabled:bg-red-700 hover:enabled:border-red-700",
    plain: "bg-transparent border-transparent text-gray-600 hover:enabled:bg-gray-100 hover:enabled:text-gray-900 [a&]:hover:bg-gray-100 [a&]:hover:text-gray-900",
  };
  const sizes = {
    md: ["h-8 px-3 text-sm", "h-8 w-8 px-0 text-sm"],
    sm: ["h-7 px-2.5 text-xs", "h-7 w-7 px-0 text-xs"],
  };
  const cls = $derived(
    `relative inline-flex shrink-0 items-center justify-center gap-1.5 whitespace-nowrap rounded-md border font-semibold leading-5 no-underline ${variants[variant]} ${sizes[size][iconOnly ? 1 : 0]} ${block ? "w-full" : ""} ${klass}`,
  );
</script>

{#snippet inner()}
  <span class="inline-flex items-center gap-1.5 {loading ? 'invisible' : ''}">
    {#if icon}<Icon name={icon} size="sm" />{/if}
    {#if iconOnly}<span class="sr-only">{title}</span>{:else}{@render children?.()}{/if}
  </span>
  {#if loading}<span class="absolute inset-0 flex items-center justify-center"><Spinner /></span>{/if}
{/snippet}

{#if href}
  <a {href} class={cls} {title} {...rest}>{@render inner()}</a>
{:else}
  <button {type} class={cls} disabled={disabled || loading} aria-busy={loading || undefined} {title} {...rest}>{@render inner()}</button>
{/if}
