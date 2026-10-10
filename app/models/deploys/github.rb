# frozen_string_literal: true

require "net/http"
require "json"

# A `repository_dispatch` on the site's repo (Settings › GitHub: the token and
# `frontend_github_repo`). The site's workflow starts a build on it:
#
#   on:
#     repository_dispatch:
#       types: [cms-publish]
#
# The dispatch's client_payload says why and what changed — {reason, site,
# changes: [Deploys::Change…]}, at most MAX_CHANGES of them, with
# `truncated: true` past that — so the workflow can build only what it must.
# GitHub answers 204 for a dispatch it accepted.
class Deploys::Github < Deploys::Provider
  EVENT_TYPE = "cms-publish"
  # GitHub caps a dispatch's payload; past this a full build is the answer anyway.
  MAX_CHANGES = 50

  def self.label = "GitHub"

  def configured?
    repo.present? && token.present?
  end

  def target = repo.presence

  def fire(reason:, changes: [])
    uri  = URI("https://api.github.com/repos/#{repo}/dispatches")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT
    request = Net::HTTP::Post.new(uri.request_uri, {
      "Authorization"        => "Bearer #{token}",
      "Accept"               => "application/vnd.github+json",
      "X-GitHub-Api-Version" => "2022-11-28",
      "Content-Type"         => "application/json",
      "User-Agent"           => "librepublish-deploy/1"
    })
    request.body = JSON.generate(event_type: EVENT_TYPE, client_payload: client_payload(reason, changes))
    attempt_from(http.request(request), nil)
  rescue StandardError => e
    attempt_from(nil, "#{e.class}: #{e.message}")
  end

  private

  def client_payload(reason, changes)
    payload = {reason: reason, site: Site.key, changes: changes.first(MAX_CHANGES)}
    payload[:truncated] = true if changes.size > MAX_CHANGES
    payload
  end

  def github = @github ||= Setting.get("github")
  def repo = github["frontend_github_repo"].to_s.strip
  def token = github["token"].to_s
end
