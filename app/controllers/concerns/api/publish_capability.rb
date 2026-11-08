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
    require_capability!("#{prefix}:publish") if record.publishing_write?
  end
end
