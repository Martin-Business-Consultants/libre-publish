# frozen_string_literal: true

# Reading the admin menu (the sidebar, layouts/shared/_sidebar) out of a response.
module AdminMenuHelpers
  def admin_menu_node(body = response.body)
    Nokogiri::HTML(body).at_css("aside#admin-menu")
  end

  # The top-level items' labels, in order.
  def menu_labels(body = response.body)
    admin_menu_node(body)&.css(".app-sidebar__link .app-sidebar__label")&.map { it.text.squish } || []
  end

  # The groups, in order, as their items name them.
  def menu_groups(body = response.body)
    admin_menu_node(body)&.css("[data-menu-group]")&.map { it["data-menu-group"] } || []
  end

  # One top-level item: its <li>.
  def menu_item(label, body = response.body)
    admin_menu_node(body)&.css(".app-sidebar__item")&.find { it.at_css(".app-sidebar__link .app-sidebar__label")&.text&.squish == label }
  end

  # One top-level item's submenu labels, in order.
  def submenu_labels(label, body = response.body)
    admin_menu_node(body)&.at_css(%(.app-sidebar__sub[aria-label="#{label}"]))&.css(".app-sidebar__sub-link")&.map { it.text.squish } || []
  end
end

RSpec.configure do |config|
  config.include AdminMenuHelpers, type: :request
end
