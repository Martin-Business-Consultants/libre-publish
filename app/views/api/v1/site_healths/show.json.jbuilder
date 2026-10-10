# frozen_string_literal: true

json.data @checks do |check|
  json.extract! check, :key, :group, :title, :detail, :ok
  json.state check.ok.nil? ? "yours_to_judge" : (check.ok ? "passes" : "fails")
  # Whether a site's build is held to it; the rest are how the CMS is run.
  json.for_site SiteHealth.for_site?(check)
end
json.meta @summary
