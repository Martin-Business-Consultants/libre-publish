# frozen_string_literal: true

# Whether someone may hand out a set of capabilities — assign a role, write
# one, give a token one, edit an account that holds one: only what they hold
# themselves, and manage:all (or the Admin role) only if they're an admin.
# Otherwise users:write, roles:write or settings:write would each be a way to
# make oneself, or a token one keeps, an admin.
module Granting
  def can_grant?(permissions)
    return true if can?(Permissions::WILDCARD)

    permissions = Array(permissions).map(&:to_s)
    permissions.exclude?(Permissions::WILDCARD) && permissions.all? { can?(it) }
  end

  def can_grant_role?(role) = role.nil? || can_grant?(role.permissions)
end
