/**
 * Reading the CMS's schema as the lock records it: its digest (the CMS's own,
 * meta.schema_digest), a digest per part and the CMS's version. Node only
 * (build time and the CLI).
 */
import type { CmsClient } from "../client.js";
import type { LiveSchema } from "../lock.js";
import type { CmsSchema, CmsSite, CmsSiteMeta } from "../types.js";
import { partDigests } from "./digest.js";

export interface LiveRead {
  schema: CmsSchema;
  live: LiveSchema;
}

export async function readLive(client: CmsClient, site: { data: CmsSite; meta: CmsSiteMeta } | null, cmsUrl: string): Promise<LiveRead> {
  const answer = await client.schema();
  const digest = answer.meta?.schema_digest;
  if (typeof digest !== "string" || !digest.startsWith("sha256:")) {
    throw new Error(`The CMS at ${cmsUrl} sent no schema digest (GET /api/v1/schema's meta.schema_digest): it's older than this version of @libre-publish/astro reads. Update the CMS.`);
  }
  return {
    schema: answer.data,
    live: {
      cmsUrl,
      apiVersion: site?.meta.api_version ?? "v1",
      cmsVersion: answer.meta.cms_version ?? site?.meta.cms_version ?? "",
      digest,
      parts: partDigests(answer.data),
    },
  };
}
