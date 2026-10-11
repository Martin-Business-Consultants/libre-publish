# frozen_string_literal: true

# How the site is served (Settings › General): one of
#
#   website      the theme draws the site; the delivery API (/api/v1) and the
#                frontend's endpoints are off. The default.
#   website_api  the theme draws the site, and what's chosen is served as
#                JSON too: each collection that says so (Collection
#                api_enabled), and the pages with the globals, all or none.
#   api_only     headless: everything live is served over /api/v1 to a
#                frontend elsewhere; the CMS's own address shows a blank page.
#
# The management API (/api/pages…, what the cms CLI, MCP and agents use) is
# on in every mode, as are the Forms plugin's public submissions and webhooks.
# An install from before this setting is given the mode it was working in by
# the migration that added it.
module Serving
  KEY = "general"
  MODES = {"website" => "Website", "website_api" => "Website + API", "api_only" => "API only"}.freeze
  DEFAULT = "website"

  module_function

  def mode
    Setting.get(KEY)["serving"].presence_in(MODES.keys) || DEFAULT
  rescue ActiveRecord::ActiveRecordError
    DEFAULT
  end

  def website? = mode != "api_only"
  def api? = mode != "website"
  def headless? = mode == "api_only"

  # Pages, with the globals a frontend draws them with (navigation, footer).
  def pages?
    case mode
    when "api_only" then true
    when "website_api" then Setting.get(KEY)["api_pages"] == true
    else false
    end
  end

  def collection?(collection)
    case mode
    when "api_only" then true
    when "website_api" then collection.try(:api_enabled?) == true
    else false
    end
  end

  # Whether the API serves this record (a page, an entry, a global).
  def record?(record)
    case record
    when CollectionEntry then collection?(record.collection)
    when Collection then collection?(record)
    else pages?
    end
  end

  # Tokens for machines that read anything in the last 30 days: what turning
  # the API off would cut off.
  def recently_used_tokens(within: 30.days)
    ServiceToken.where(revoked_at: nil).where("last_used_at > ?", within.ago).order(last_used_at: :desc).to_a
  end
end
