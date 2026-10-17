<script>
  // A notice (badges.css .notice): info, success, warning, danger.
  import Icon from "./Icon.svelte";
  let { tone = "info", icon = null, children, class: klass = "" } = $props();
  const tones = {
    info: "bg-accent-50 border-accent-200 text-accent-800",
    success: "bg-green-50 border-green-200 text-green-800",
    warning: "bg-yellow-50 border-yellow-200 text-yellow-800",
    danger: "bg-red-50 border-red-200 text-red-800",
  };
  const icons = { info: "help-circle", success: "check-circle", warning: "bell-alert", danger: "close-circle" };
</script>

<div class="flex items-start gap-3 rounded-lg border px-4 py-3 text-sm leading-5 {tones[tone]} {klass}" role={tone === "danger" ? "alert" : "status"}>
  <Icon name={icon || icons[tone]} size="md" />
  <div class="min-w-0 flex-1">{@render children()}</div>
</div>
