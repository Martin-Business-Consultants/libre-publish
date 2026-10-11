# frozen_string_literal: true

# Active Storage's direct uploads (the media library's uploads go straight to
# storage, then the form posts the signed ids), only for someone signed in
# who can add to the library, and no bigger than an upload may be. Rails'
# own controller takes them from anyone, which let a visitor fill the disk.
class DirectUploadsController < ActiveStorage::DirectUploadsController
  MAX_BYTES = 200.megabytes

  before_action :require_library_writer
  before_action :refuse_oversized

  private

  def require_library_writer
    session = Session.find_by_id(cookies.signed[:session_token])
    user = session&.user unless session.nil? || session.expired?
    head :unauthorized unless user&.can?("assets:write")
  end

  def refuse_oversized
    size = params.dig(:blob, :byte_size).to_i
    return if size.positive? && size <= MAX_BYTES

    render json: {error: "Files can be at most #{MAX_BYTES / 1.megabyte} MB."}, status: :unprocessable_content
  end
end
