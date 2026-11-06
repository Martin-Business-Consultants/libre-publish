# frozen_string_literal: true

# Each check as the Go core gives it — key, state and a message to show — and
# this CMS's own detail beside them (group, title, detail, ok, for_site).
json.data @checks do |check|
  json.extract! check, :key, :group, :title, :detail, :ok
  json.state check.ok.nil? ? "yours_to_judge" : (check.ok ? "passes" : "fails")
  # The check, and for one that doesn't pass, what to do about it.
  json.message check.ok ? check.title.to_s : [check.title, check.detail].compact_blank.join(": ")
  # Whether a site's build is held to it; the rest are how the CMS is run.
  json.for_site SiteHealth.for_site?(check)
end
json.meta @summary
