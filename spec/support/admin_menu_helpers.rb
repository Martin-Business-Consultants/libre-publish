# frozen_string_literal: true

# Reading the admin menu (the sidebar, layouts/shared/_sidebar) out of a response.
module AdminMenuHelpers
  # The top-level items' labels, in order.
  def menu_labels(body = response.body)
    admin_menu(body).scan(%r{<a [^>]*data-menu-group="[^"]*"[^>]*>.*?<span class="sidebar__label[ "][^>]*>([^<]+)</span>}m).flatten
  end

  # The groups, in order, as their items name them.
  def menu_groups(body = response.body)
    admin_menu(body).scan(/data-menu-group="([^"]*)"/).flatten.uniq
  end

  # One top-level item's submenu labels, in order.
  def submenu_labels(label, body = response.body)
    list = admin_menu(body)[%r{<ul class="sidebar__sub[ "][^>]*aria-label="#{Regexp.escape(label)}">.*?</ul>}m].to_s
    list.scan(%r{class="sidebar__sub-link[ "][^>]*>(.*?)</a>}m).flatten.map { it.gsub(/<[^>]+>/, "").squish }
  end

  def admin_menu(body) = body[%r{<nav id="admin-menu".*?</nav>}m].to_s
end

RSpec.configure do |config|
  config.include AdminMenuHelpers, type: :request
end
