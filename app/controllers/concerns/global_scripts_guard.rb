# frozen_string_literal: true

# The Scripts global goes into every page of the site as written (analytics,
# a chat widget: website_scripts), so whoever writes it can run script in
# every visitor's browser, and in an admin's while they look at the site.
# Writing it takes its own capability, globals:scripts, which only admins
# hold unless a role is given it; globals:write is for the rest.
module GlobalScriptsGuard
  extend ActiveSupport::Concern

  CAPABILITY = "globals:scripts"

  private

  # Before any write that touches it: editing it, or a global being made, or
  # renamed, into it.
  def guard_scripts_global!
    slugs = [@global&.slug, params.dig(:global, :slug)].compact.map(&:to_s)
    return unless slugs.include?(Global::SCRIPTS_SLUG)
    return if Current.user&.can?(CAPABILITY)

    raise Authorization::Forbidden, CAPABILITY
  end
end
