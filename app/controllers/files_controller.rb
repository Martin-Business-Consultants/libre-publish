# frozen_string_literal: true

# GET /files/<key>/<name> and /files/<key>/w<width>/<name> — a media library
# file at a stable address on the CMS's host, and an image's renditions, as
# the Go core serves them: the delivery API's asset URLs (Asset::Delivery).
# @librepublish/astro allows the CMS's /files/** as remote images and copies
# what a built page links there into the site (its localFiles), so the live
# site serves its own. Each answer redirects to the file as Active Storage
# serves it. Only an asset's file is served: the key alone, which nothing
# but an asset's URL gives out, opens nothing else.
class FilesController < ApplicationController
  skip_before_action :authenticate, raise: false
  # Public, as the asset URLs the delivery API gives every site are.
  skip_authorization

  def show
    blob = ActiveStorage::Blob.joins(:attachments).where(active_storage_attachments: {record_type: "Asset"}).find_by!(key: params[:key])
    width = params[:rendition].to_s.delete_prefix("w").to_i
    if width.positive? && blob.variable? && Asset::Delivery::RENDITION_WIDTHS.include?(width)
      redirect_to rails_representation_path(blob.variant(resize_to_limit: [width, nil]), only_path: true)
    elsif width.positive?
      head :not_found
    else
      redirect_to rails_blob_path(blob, only_path: true)
    end
  end
end
