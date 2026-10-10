# frozen_string_literal: true

# The API's side of the record's publish gate (PublishGated): a write that
# changes live content, or publishes or schedules a draft, needs
# `<resource>:publish`, and is a 403 without it. Nothing is queued for review.
#
#   @page.assign_attributes(page_params)
#   require_publish_capability!(@page, prefix: "pages")
#   @page.save!
module Api::PublishCapability
  extend ActiveSupport::Concern

  private

  def require_publish_capability!(record, prefix:)
    raise Authorization::Forbidden, "#{prefix}:publish" if record.publishing_write? && !can_publish?(prefix)
  end

  # Mirrors Authorization#granted? — a token is bounded by its owner's role,
  # and a session falls through to the signed-in user.
  def can_publish?(prefix)
    capability = "#{prefix}:publish"
    if Current.api_token
      Current.api_token.can?(capability)
    else
      Current.user&.can?(capability) || Current.api_user&.can?(capability)
    end
  end
end
