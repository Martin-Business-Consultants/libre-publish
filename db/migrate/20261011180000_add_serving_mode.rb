# frozen_string_literal: true

# How the site is served (Serving): a collection can be offered over the API
# on its own, and an install that predates the choice gets the mode it was
# working in, so nothing it served goes dark on update:
#
#   no theme drawing the site                      api_only
#   a theme, and a machine token read lately       website_api, everything on
#   a theme, and no machine reading the API        website
class AddServingMode < ActiveRecord::Migration[8.1]
  class Setting < ActiveRecord::Base
    self.table_name = "settings"
  end

  def up
    add_column :collections, :api_enabled, :boolean, default: false, null: false

    general = Setting.find_or_initialize_by(key: "general")
    data = general.data.to_h
    return if data["serving"].present?

    theme = defined?(::Website) && (::Website.enabled? rescue false)
    read_lately = select_value("SELECT COUNT(*) FROM service_tokens WHERE revoked_at IS NULL AND last_used_at > #{connection.quote(30.days.ago)}").to_i.positive?

    data["serving"] =
      if !theme then "api_only"
      elsif read_lately then "website_api"
      else "website"
      end
    if data["serving"] == "website_api"
      data["api_pages"] = true
      execute "UPDATE collections SET api_enabled = 1"
    end
    general.data = data
    general.save!
  end

  def down
    remove_column :collections, :api_enabled
  end
end
