<script>
  // An icon from src/icons, drawn as a mask over the text color (the Rails
  // admin's icons, inlined into the build).
  const urls = import.meta.glob("../../icons/*.svg", { eager: true, query: "?url", import: "default" });
  const byName = Object.fromEntries(Object.entries(urls).map(([p, u]) => [p.split("/").pop().replace(".svg", ""), u]));

  /** @type {{ name: string, size?: "xs"|"sm"|"md"|"lg"|"xl", class?: string }} */
  let { name, size = "sm", class: klass = "" } = $props();
  const px = { xs: "0.75rem", sm: "1rem", md: "1.25rem", lg: "1.5rem", xl: "2.5rem" };
</script>

<span class="icon {klass}" style="--svg: url({JSON.stringify(byName[name] || '')}); --icon-size: {px[size]}" aria-hidden="true"></span>
