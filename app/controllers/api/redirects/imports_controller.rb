# frozen_string_literal: true

require "csv"

# POST /api/redirects/import — accepts the CSV as a raw request body or as an
# uploaded `file` param, so `cms redirects import < redirects.csv` works as well
# as a multipart post. Upserts by source path (Redirect::Import).
class Api::Redirects::ImportsController < Api::BaseController
  requires_capability "redirects:write", only: :create

  def create
    csv, byte_size = uploaded_csv
    if Redirect::Import.too_big?(byte_size)
      render json: {error: "too_large", message: "The CSV is over #{Redirect::Import::MAX_BYTES / 1.megabyte} MB"}, status: :content_too_large
    elsif byte_size.to_i.zero?
      render json: {error: "invalid", message: "No CSV supplied"}, status: :unprocessable_content
    else
      @import = Redirect.import_csv(csv)
      Redirect.track_event(:imported, created: @import.created, updated: @import.updated, errored: @import.errored)
    end
  rescue CSV::MalformedCSVError => e
    render json: {error: "invalid_csv", message: e.message}, status: :unprocessable_content
  end

  private

  # The CSV as an IO to read rows from, and its size.
  def uploaded_csv
    file = params[:file]
    return [file.to_io, file.size] if file.respond_to?(:to_io)

    request.body.rewind
    [request.body, request.content_length || request.body.size]
  end
end
