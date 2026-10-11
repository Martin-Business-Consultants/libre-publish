# frozen_string_literal: true

# For what hands over the whole install: a backup holds every account, every
# secret (and an archive of the data directory, the key that decrypts them),
# so whoever can download one can become anyone. Only a person or token on
# the Admin role (manage:all), whatever other capability the action names.
module AdminOnly
  extend ActiveSupport::Concern

  class_methods do
    def admin_only(**options)
      before_action :require_admin_principal!, **options
    end
  end

  private

  def require_admin_principal!
    principal = Current.user || Current.api_token
    raise Authorization::Forbidden, Permissions::WILDCARD unless principal&.can?(Permissions::WILDCARD)
  end
end
