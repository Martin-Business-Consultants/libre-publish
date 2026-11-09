/**
 * What libre-publish's delivery API (/api/v1) answers, as its contract
 * (contracts/delivery/*.json, recorded by spec/contracts/delivery_contract_spec.rb)
 * has it. Every answer is `{ data, meta, included? }`;
 * `included.assets` holds the assets the records point at, by id.
 *
 * These are the open, structural shapes. The fields a site defines (block
 * data, frontmatter, global data) are typed exactly — and validated — from
 * the CMS's schema: see the generated "libre-publish:types" module and the
 * content loaders (createSchema).
 */

export interface Envelope<T, M = Record<string, unknown>> {
  data: T;
  meta: M;
  included?: { assets?: Record<string, CmsAsset>; entries?: Record<string, CmsEntry>; pages?: Record<string, CmsPage> };
}

export interface ListMeta {
  page: number;
  per: number;
  total: number;
  next_page: number | null;
}

/** An asset as `included.assets` carries it (the Media plugin's Asset::Delivery). */
export interface CmsAsset {
  id: number;
  url: string;
  original: string;
  filename: string;
  content_type: string;
  byte_size: number;
  alt: string;
  width: number | null;
  height: number | null;
  /** The media library folder it's in, e.g. "/" or "/team". */
  folder: string;
  /** Images the CMS can resize: width-limited renditions by name ("w640" …), absolute URLs. Empty for SVGs. */
  variants?: Record<string, string>;
  /** Images only: the renditions for a srcset. */
  srcset?: { width: number; descriptor: string; url: string }[];
  thumb_url?: string;
  /** Images only: the focal point, 0–1 from the left and top. */
  focal_x?: number;
  focal_y?: number;
}

export interface CmsBlock<D = Record<string, unknown>> {
  /** Top-level blocks carry one; blocks nested in a `blocks` field may not. */
  id?: string;
  type: string;
  version?: number;
  data: D;
  /** What the CMS resolved for the block: a collection_list's entries, a contact_info's contact. */
  resolved?: CmsCollectionList | CmsContactInfo;
}

/** An entry as a collection_list block lists it (Page::BlockExpansion). */
export interface CmsListedEntry<F = Record<string, unknown>> {
  id: number;
  slug: string;
  title: string;
  status: string;
  locale: string;
  collection: string;
  url: string;
  frontmatter: F;
  body_markdown: string;
  published_at: string | null;
  updated_at: string;
  category: CmsTerm | null;
  tags: CmsTerm[];
}

/** A collection_list block's `resolved`. */
export interface CmsCollectionList {
  collection?: { slug: string; name: string };
  entries: CmsListedEntry[];
  total: number;
  groups?: { key: string; label: string; entries: CmsListedEntry[] }[];
  /** Set when the block names a collection that doesn't exist (with `slug`). */
  error?: string;
  slug?: string;
}

/** Settings › General's contact details. */
export interface CmsContact {
  title?: string;
  phone?: string;
  email?: string;
  address_line1?: string;
  city?: string;
  state?: string;
  zip?: string;
}

/** A contact_info block's `resolved`. */
export interface CmsContactInfo { contact: CmsContact }

export interface CmsTerm { id: number; slug: string; title: string }

export interface CmsTranslation { locale: string; path: string }

export interface CmsPage<F = Record<string, unknown>, S = Record<string, unknown>, B = CmsBlock> {
  id: number;
  path: string;
  slug: string;
  title: string;
  locale: string;
  /** Where it's served: site-relative ("/", "/about"), or an absolute SEO canonical. */
  url: string;
  blocks: B[];
  frontmatter: F;
  seo: S;
  published_at: string | null;
  updated_at: string;
  category: CmsTerm | null;
  tags: CmsTerm[];
  translations: CmsTranslation[];
}

export interface CmsEntry<F = Record<string, unknown>, S = Record<string, unknown>, B = CmsBlock> {
  id: number;
  slug: string;
  title: string;
  locale: string;
  collection: string;
  url: string;
  frontmatter: F;
  body_markdown: string;
  blocks: B[] | null;
  seo: S;
  published_at: string | null;
  updated_at: string;
  category: CmsTerm | null;
  tags: CmsTerm[];
  translations: CmsTranslation[];
}

export interface CmsGlobal<D = Record<string, unknown>> {
  id: number;
  slug: string;
  name: string;
  data: D;
  updated_at: string;
}

export interface CmsCollection {
  id: number;
  slug: string;
  name: string;
  enable_blocks: boolean;
  routable: boolean;
  fields: unknown[];
}

export interface CmsSiteMeta {
  /** The CMS's own address (APP_HOST), which asset URLs start with. */
  cms_url: string;
  /** The CMS's version, e.g. "1.36.0". */
  cms_version: string;
  /** The delivery API's version: "v1". */
  api_version: string;
}

export interface CmsSite {
  name: string;
  description: string;
  /** The public site's URL (Settings › General); "" until it's set. */
  url: string;
  default_locale: string;
  /** Every locale but the default is a path prefix: /fr/… */
  locales: string[];
  contact: CmsContact;
  /** The enabled plugins' keys, e.g. "forms", "media". */
  plugins: string[];
  /** What each enabled plugin tells a site. */
  plugin_config: Record<string, Record<string, unknown>>;
}

/** The widths the CMS renders image variants at (an asset's `variants`: w640, w1280, w1920). */
export const IMAGE_WIDTHS = [640, 1280, 1920] as const;

export interface CmsContent {
  pages: CmsPage[];
  entries: CmsEntry[];
  globals: CmsGlobal[];
  /** Only on a delta (`?since=`): what stopped being live. */
  removed?: {
    pages: { id: number; path: string }[];
    entries: { id: number; collection: string; slug: string }[];
    globals: { id: number; slug: string }[];
  };
}

export interface ContentMeta { cursor: string; full: boolean; since: string }

export interface CmsRobots {
  text: string;
  mode: "generated" | "custom";
}

/** One URL of GET /api/v1/sitemap. `url` is absolute once Settings › General has the site's URL. */
export interface CmsSitemapUrl {
  url: string;
  path: string;
  lastmod: string;
  changefreq: string;
  priority: number;
  locale: string;
  alternates: { locale: string; url: string }[];
}

export interface CmsRedirect { source: string; destination: string; status: number; wildcard: boolean }

/** One of GET /api/v1/site_health's checks. */
export interface CmsHealthCheck {
  key: string;
  state: "passes" | "fails" | "yours_to_judge";
  message: string;
}

/** A JSON Schema (2020-12) as the CMS writes it (BlockType::Validator.json_schema_for). */
export interface JsonSchema {
  $schema?: string;
  type?: string | string[];
  title?: string;
  description?: string;
  enum?: unknown[];
  const?: unknown;
  format?: string;
  properties?: Record<string, JsonSchema>;
  required?: string[];
  additionalProperties?: boolean | JsonSchema;
  items?: JsonSchema;
  oneOf?: JsonSchema[];
  anyOf?: JsonSchema[];
  "x-cms-type"?: string;
  [key: string]: unknown;
}

/**
 * GET /api/v1/schema's `data`, as libre-publish sends it: each part's JSON
 * Schema one level down, beside what the CMS says about the part. Its
 * digest (meta.schema_digest, X-CMS-Schema-Digest) is of exactly this.
 */
export interface CmsSchema {
  $schema?: string;
  /** Each block type, by slug: its label, version, whether it's retired, and its data's JSON Schema. */
  block_types: Record<string, { title: string; version: number; deprecated: boolean; data: JsonSchema }>;
  /** Each served collection, by slug: its frontmatter's JSON Schema. */
  collections: Record<string, { title: string; enable_blocks: boolean; routable: boolean; frontmatter: JsonSchema }>;
  /** Each global, by slug: its data's JSON Schema. */
  globals: Record<string, { title: string; data: JsonSchema }>;
  /** Pages that carry fields of their own, by path. */
  pages: Record<string, { title: string; frontmatter: JsonSchema }>;
  seo: JsonSchema;
}

/** The schema as the validators and type generator read it: each part its JSON Schema, titled. */
export interface NormalizedSchema {
  blocks: Record<string, JsonSchema>;
  collections: Record<string, JsonSchema>;
  globals: Record<string, JsonSchema>;
  pages: Record<string, JsonSchema>;
  seo: JsonSchema;
}

/** CmsSchema → NormalizedSchema: each part's JSON Schema, carrying the part's title. */
export function normalizeSchema(schema: CmsSchema): NormalizedSchema {
  const titled = (json: JsonSchema | undefined, title: string | undefined): JsonSchema =>
    ({ type: "object", properties: {}, additionalProperties: false, ...(json ?? {}), ...(title ? { title } : {}) });
  const map = <T>(parts: Record<string, T> | undefined, pick: (part: T) => [JsonSchema | undefined, string | undefined]) =>
    Object.fromEntries(Object.entries(parts ?? {}).map(([key, part]) => [key, titled(...pick(part))]));
  return {
    blocks: map(schema.block_types, (part) => [part.data, part.title]),
    collections: map(schema.collections, (part) => [part.frontmatter, part.title]),
    globals: map(schema.globals, (part) => [part.data, part.title]),
    pages: map(schema.pages, (part) => [part.frontmatter, part.title]),
    seo: schema.seo ?? { type: "object", properties: {}, additionalProperties: false },
  };
}

/** GET /api/v1/schema's `meta`: the schema's digest (docs/delivery-api.md) and the CMS's version. */
export interface CmsSchemaMeta { schema_digest: string; cms_version: string }
