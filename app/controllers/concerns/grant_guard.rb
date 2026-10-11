# frozen_string_literal: true

# Refuses handing out more than the person (or token) asking holds
# (Granting): an account given a role, a role written, a token issued or
# revealed. 403, like any other capability they lack.
module GrantGuard
  extend ActiveSupport::Concern

  private

  def granting_principal = Current.user || Current.api_token

  def refuse_unless_grantable!(permissions)
    return if granting_principal&.can_grant?(permissions)

    raise Authorization::Forbidden, (Array(permissions).include?(Permissions::WILDCARD) ? Permissions::WILDCARD : "the capabilities it holds")
  end

  def refuse_unless_role_grantable!(role) = role && refuse_unless_grantable!(role.permissions)
end
