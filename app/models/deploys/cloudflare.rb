# frozen_string_literal: true

# A Cloudflare deploy hook: Pages (project › Settings › Builds › Deploy hooks)
# or Workers Builds (worker › Settings › Build › Deploy hooks). Both are a URL
# an empty POST starts a build at, so this is the build hook, named for where
# the URL comes from.
class Deploys::Cloudflare < Deploys::BuildHook
  def self.label = "Cloudflare (Pages or Workers Builds deploy hook)"
end
