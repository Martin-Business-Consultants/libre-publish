// The admin wears the site's branding (Settings › Brand), as the Rails
// admin did with /branding.css: the primary color for buttons, links, focus
// and what's current; the secondary color tinting the grays; the font; the
// corners; the shadow; the logo in the bar and on the sign-in page; the
// favicon; and the top bar dark in light mode too.
//
// The values come from /api/session, which the server has already checked.
// They're checked again here and the CSS is rebuilt from the checked hex
// digits and this file's own tables — no string from the API goes into the
// stylesheet as it came. The overrides go in one <style> after app.css,
// for light (:root) and dark (.dark) alike, so dark mode keeps working.

export const FONTS = ["Inter", "DM Sans", "Manrope", "Playfair Display", "Lora"];
export const SIZES = ["none", "small", "medium", "large"];
export const TOP_BARS = ["match", "dark"];

const SANS = '-apple-system, BlinkMacSystemFont, "Segoe UI", "Noto Sans", Helvetica, Arial, sans-serif';
const SERIF = 'Georgia, "Times New Roman", serif';
// Bundled (@fontsource-variable), loaded only when chosen.
const FONT_FACES = {
  Inter: { family: `"Inter Variable", ${SANS}`, load: () => Promise.resolve() },
  "DM Sans": { family: `"DM Sans Variable", ${SANS}`, load: () => import("@fontsource-variable/dm-sans") },
  Manrope: { family: `"Manrope Variable", ${SANS}`, load: () => import("@fontsource-variable/manrope") },
  "Playfair Display": { family: `"Playfair Display Variable", ${SERIF}`, load: () => import("@fontsource-variable/playfair-display") },
  Lora: { family: `"Lora Variable", ${SERIF}`, load: () => import("@fontsource-variable/lora") },
};

// Corners: shadcn's --radius (a panel's; the rest are fractions of it).
const RADII = { none: "0", small: "0.25rem", medium: "0.5rem", large: "0.875rem" };

// Shadow: under panels and controls, and under what floats (menus,
// dialogs, popovers). Tailwind writes shadows into its utilities, so these
// replace the utilities' own.
const SHADOWS = {
  none: { surface: "0 0 #0000", overlay: "0 0 #0000" },
  small: { surface: "0 1px 2px 0 rgb(0 0 0 / 0.05)", overlay: "0 4px 12px -2px rgb(0 0 0 / 0.1), 0 2px 4px -2px rgb(0 0 0 / 0.06)" },
  medium: { surface: "0 1px 3px 0 rgb(0 0 0 / 0.1), 0 1px 2px -1px rgb(0 0 0 / 0.1)", overlay: "0 0 0 1px rgb(0 0 0 / 0.04), 0 10px 16px rgb(0 0 0 / 0.08), 0 2px 6px rgb(0 0 0 / 0.12)" },
  large: { surface: "0 10px 15px -3px rgb(0 0 0 / 0.1), 0 4px 6px -4px rgb(0 0 0 / 0.1)", overlay: "0 25px 50px -12px rgb(0 0 0 / 0.25), 0 8px 16px -8px rgb(0 0 0 / 0.15)" },
};

// ---- colors --------------------------------------------------------------

/** A hex color (#rgb or #rrggbb) as #rrggbb, or null. */
export function hexColor(v) {
  const m = typeof v === "string" && /^#([0-9a-f]{3}|[0-9a-f]{6})$/i.exec(v.trim());
  if (!m) return null;
  return "#" + (m[1].length === 3 ? [...m[1]].map((d) => d + d).join("") : m[1]).toLowerCase();
}

const rgb = (hex) => [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255);
const linear = (v) => (v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4);
const toHex = (c) => "#" + c.map((v) => Math.round(Math.min(1, Math.max(0, v)) * 255).toString(16).padStart(2, "0")).join("");

/** WCAG relative luminance. */
function luminance(hex) {
  const [r, g, b] = rgb(hex).map(linear);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/** Text that reads on a fill: near-black on a light one, else white. */
const onFill = (hex) => (luminance(hex) > 0.45 ? "#1c1917" : "#ffffff");

/** hex mixed toward white by t (0–1). */
const lighten = (hex, t) => toHex(rgb(hex).map((v) => v + (1 - v) * t));

/** The color's OKLCH chroma and hue. */
function oklch(hex) {
  const [r, g, b] = rgb(hex).map(linear);
  const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
  const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
  const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  const a = 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s;
  const bb = 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s;
  return { c: Math.hypot(a, bb), h: ((Math.atan2(bb, a) * 180) / Math.PI + 360) % 360 };
}

// The neutral tokens (app.css) by lightness, light and dark; alpha ones
// (dark borders) stay as they are.
const NEUTRALS = {
  light: { background: 1, foreground: 0.145, card: 1, "card-foreground": 0.145, popover: 1, "popover-foreground": 0.145,
    primary: 0.205, "primary-foreground": 0.985, secondary: 0.97, "secondary-foreground": 0.205, muted: 0.97, "muted-foreground": 0.556,
    accent: 0.97, "accent-foreground": 0.205, border: 0.922, input: 0.922, ring: 0.708, sidebar: 0.985, "sidebar-foreground": 0.145,
    "sidebar-primary": 0.205, "sidebar-primary-foreground": 0.985, "sidebar-accent": 0.97, "sidebar-accent-foreground": 0.205,
    "sidebar-border": 0.922, "sidebar-ring": 0.708 },
  dark: { background: 0.145, foreground: 0.985, card: 0.205, "card-foreground": 0.985, popover: 0.205, "popover-foreground": 0.985,
    primary: 0.922, "primary-foreground": 0.205, secondary: 0.269, "secondary-foreground": 0.985, muted: 0.269, "muted-foreground": 0.708,
    accent: 0.269, "accent-foreground": 0.985, ring: 0.556, sidebar: 0.205, "sidebar-foreground": 0.985, "sidebar-accent": 0.269,
    "sidebar-accent-foreground": 0.985, "sidebar-ring": 0.556 },
};

// ---- the branding --------------------------------------------------------

const safeURL = (u) => (typeof u === "string" && /^(https?:\/\/|\/(?!\/))/i.test(u) ? u : null);
const oneOf = (list, v) => (list.includes(v) ? v : null);

/** The branding with only values that pass the checks: colors as #rrggbb, logo and favicon as image URLs. */
export function checked(b) {
  b = b && typeof b === "object" ? b : {};
  const img = (a) => (a && typeof a === "object" ? safeURL(a.url) && { url: safeURL(a.url), thumb: safeURL(a.thumb_url) || safeURL(a.url), alt: String(a.alt || ""), width: a.width, height: a.height } : null);
  return {
    logo: img(b.logo), favicon: img(b.favicon),
    primary_color: hexColor(b.primary_color), secondary_color: hexColor(b.secondary_color),
    font: oneOf(FONTS, b.font), border_radius: oneOf(SIZES, b.border_radius), box_shadow: oneOf(SIZES, b.box_shadow),
    top_bar: oneOf(TOP_BARS, b.top_bar),
  };
}

/** The admin's overrides for a checked branding, as CSS ("" for none). */
export function stylesheet(b) {
  const light = [], dark = [], root = [], rules = [];
  if (b.secondary_color) {
    // The grays lean to the secondary color's hue, faintly: more in the
    // darker tones, less in the near-white surfaces.
    const { c, h } = oklch(b.secondary_color);
    const tint = Math.min(c * 0.25, 0.025);
    if (tint > 0.002) {
      const tone = (l) => `oklch(${l} ${(tint * (l > 0.9 ? 0.4 : 1)).toFixed(4)} ${h.toFixed(1)})`;
      for (const [k, l] of Object.entries(NEUTRALS.light)) light.push(`--${k}:${tone(l)}`);
      for (const [k, l] of Object.entries(NEUTRALS.dark)) dark.push(`--${k}:${tone(l)}`);
    }
  }
  if (b.primary_color) {
    const p = b.primary_color;
    // In the dark a dark primary is lifted until it stands off the ground.
    let d = p;
    for (let t = 0.1; luminance(d) < 0.12 && t <= 0.7; t += 0.1) d = lighten(p, t);
    for (const [list, c] of [[light, p], [dark, d]]) {
      list.push(`--primary:${c}`, `--primary-foreground:${onFill(c)}`, `--ring:${c}`, `--sidebar-primary:${c}`,
        `--sidebar-primary-foreground:${onFill(c)}`, `--sidebar-ring:${c}`);
    }
  }
  if (b.font) root.push(`--admin-font:${FONT_FACES[b.font].family}`);
  if (b.border_radius) root.push(`--radius:${RADII[b.border_radius]}`);
  if (b.box_shadow) {
    const s = SHADOWS[b.box_shadow];
    rules.push(`.shadow-xs,.shadow-sm{--tw-shadow:${s.surface}}`, `.shadow-md,.shadow-lg,.shadow-xl,.shadow-2xl{--tw-shadow:${s.overlay}}`);
  }
  const out = [];
  if (root.length || light.length) out.push(`:root{${[...root, ...light].join(";")}}`);
  if (dark.length) out.push(`.dark{${dark.join(";")}}`);
  return out.concat(rules).join("\n");
}

class Brand {
  /** What's saved (checked). */
  saved = $state(checked({}));
  /** What the admin wears now: what's saved, or a preview of what's being edited. */
  current = $state(checked({}));

  /** Wear the saved branding (from /api/session). */
  set(raw) {
    this.saved = checked(raw);
    this.wear(this.saved);
  }

  /** Wear a draft without saving it (Settings › Brand's live preview). */
  preview(raw) { this.wear(checked(raw)); }

  /** Back to what's saved. */
  reset() { this.wear(this.saved); }

  wear(b) {
    this.current = b;
    if (typeof document === "undefined") return;
    if (b.font) FONT_FACES[b.font].load().catch(() => {});
    let style = document.getElementById("lp-branding");
    if (!style) {
      style = document.createElement("style");
      style.id = "lp-branding";
      document.head.append(style);
    }
    style.textContent = stylesheet(b);
    let icon = document.getElementById("lp-favicon");
    if (b.favicon) {
      if (!icon) {
        icon = document.createElement("link");
        icon.id = "lp-favicon";
        icon.rel = "icon";
        document.head.append(icon);
      }
      icon.href = b.favicon.thumb;
    } else icon?.remove();
  }
}

export const brand = new Brand();
