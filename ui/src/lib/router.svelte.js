// A hash router: #/pages/edit/about?status=draft. Routes are patterns with
// :params and a trailing *rest; the first that matches wins.
class Router {
  path = $state("/");
  query = $state(new URLSearchParams());

  constructor() {
    const read = () => {
      const raw = location.hash.replace(/^#/, "") || "/";
      const [p, q] = raw.split("?");
      this.path = p || "/";
      this.query = new URLSearchParams(q || "");
    };
    read();
    addEventListener("hashchange", read);
  }

  match(routes) {
    for (const [pattern, component] of routes) {
      const params = matchPattern(pattern, this.path);
      if (params) return { component, params };
    }
    return null;
  }
}

function matchPattern(pattern, path) {
  const a = pattern.split("/").filter(Boolean);
  const b = path.split("/").filter(Boolean);
  const params = {};
  for (let i = 0; i < a.length; i++) {
    if (a[i] === "*rest") { params.rest = b.slice(i).map(decodeURIComponent).join("/"); return params.rest ? params : null; }
    if (b[i] === undefined) return null;
    if (a[i].startsWith(":")) params[a[i].slice(1)] = decodeURIComponent(b[i]);
    else if (a[i] !== b[i]) return null;
  }
  return a.length === b.length ? params : null;
}

export const router = new Router();

// href("/pages", {status: "draft"}) → "#/pages?status=draft"
export function href(path, query) {
  const q = query ? new URLSearchParams(Object.entries(query).filter(([, v]) => v !== "" && v != null)).toString() : "";
  return "#" + path + (q ? "?" + q : "");
}

export function go(path, query) { location.hash = href(path, query).slice(1); }

// The current query with one key changed (a filter link).
export function withQuery(changes) {
  const q = new URLSearchParams(router.query);
  for (const [k, v] of Object.entries(changes)) {
    if (v === "" || v == null) q.delete(k); else q.set(k, v);
  }
  q.delete("page");
  if ("page" in changes && changes.page != null) q.set("page", changes.page);
  const s = q.toString();
  return "#" + router.path + (s ? "?" + s : "");
}
