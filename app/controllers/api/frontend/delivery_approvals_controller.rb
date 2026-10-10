# frozen_string_literal: true

# POST /api/frontend/delivery_approval — takes what the site's last build
# reported about how it renders and where it takes purges, the change a build
# can't make on its own (Frontend.record_build). `approved` is false when
# nothing was waiting.
class Api::Frontend::DeliveryApprovalsController < Api::BaseController
  enforce_authorization
  requires_capability "settings:write", only: :create

  def create
    @approved = Frontend.approve_delivery!
  end
end
