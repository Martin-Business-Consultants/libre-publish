# frozen_string_literal: true

# Unpacks a bulk upload's zip into assets (BulkUpload::Unpackable).
class BulkUpload::UnpackJob < ApplicationJob
  queue_as :default

  def perform(bulk_upload_id)
    BulkUpload.find(bulk_upload_id).unpack_now
  end
end
