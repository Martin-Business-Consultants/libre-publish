# frozen_string_literal: true

# Loads the service token a nested Settings::ServiceTokens resource acts on.
module Settings::ServiceTokenScoped
  extend ActiveSupport::Concern

  included do
    include GrantGuard
    before_action :set_service_token
    # Revealing, rotating or revoking a token on a role you couldn't give.
    before_action -> { refuse_unless_role_grantable!(@token.role) }
  end

  private

  def set_service_token
    @token = ServiceToken.find(params[:service_token_id])
  end
end
