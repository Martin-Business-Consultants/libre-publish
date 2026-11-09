/**
 * What a signed POST to /_cms/webhook asks for. Two senders reach it:
 *
 *   - the CMS's deploy (Settings › Deploy, a site rendered on demand,
 *     Deploys::Purge): `{ "event": "cms.purge", "reason": "page.published",
 *     "all": false, "tags": [...], "changes": [...] }` — purge those cache
 *     tags, or everything when `all` is true ("Deploy now"), or when it
 *     names no tags and doesn't say;
 *   - a webhook (Settings › Webhooks) pointed at it, in the envelope
 *     spec/fixtures/contracts/webhook_contract.json pins, `{ event, tenant,
 *     delivered_at, data }`: page.* and entry.* purge what they name,
 *     global.updated its global, and `schema.changed` purges nothing — the
 *     site's code was checked against the old schema, so it needs a rebuild
 *     (and a `libre-publish-astro sync`), which the answer says.
 *
 * Pure, so it can be tested without a Worker.
 */
export type PurgePlan =
  | { kind: "purge"; all: boolean; tags: string[] }
  | { kind: "rebuild"; reason: string; schema_digest?: string }
  | { kind: "ignore"; event: string | null };

export function plan(payload: unknown): PurgePlan {
  const body = (payload ?? {}) as Record<string, unknown>;
  const event = typeof body.event === "string" ? body.event : null;

  if (!event || event === "cms.purge") {
    const tags = Array.isArray(body.tags) ? body.tags.filter((tag): tag is string => typeof tag === "string" && tag !== "") : [];
    const all = body.all === true || (body.all !== false && tags.length === 0);
    return { kind: "purge", all, tags: all ? [] : tags };
  }

  const data = (body.data ?? {}) as Record<string, unknown>;
  const text = (key: string) => (typeof data[key] === "string" ? (data[key] as string) : "");
  if (event === "schema.changed") {
    return { kind: "rebuild", reason: "The CMS's schema changed: run `npx libre-publish-astro sync`, check the site and rebuild it.", schema_digest: text("schema_digest") || undefined };
  }
  if (event.startsWith("page.") && text("path")) {
    return { kind: "purge", all: false, tags: [`page:${text("path")}`, "pages", "sitemap"] };
  }
  if (event.startsWith("entry.") && text("collection_slug") && text("slug")) {
    const collection = text("collection_slug");
    return { kind: "purge", all: false, tags: [`entry:${collection}/${text("slug")}`, `collection:${collection}`, "sitemap"] };
  }
  if (event === "global.updated" && text("slug")) return { kind: "purge", all: false, tags: [`global:${text("slug")}`] };
  return { kind: "ignore", event };
}
