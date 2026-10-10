# frozen_string_literal: true

require "csv"

# Tools › Redirects › Import: upserts rules from a CSV in the export's format.
class Tools::Redirects::ImportsController < ApplicationController
  requires_capability "redirects:write", only: :create

  def create
    file = params[:file]

    if file.respond_to?(:to_io) && Redirect::Import.too_big?(file.size)
      redirect_to tools_redirects_path, alert: "That CSV is over #{Redirect::Import::MAX_BYTES / 1.megabyte} MB."
    elsif file.respond_to?(:to_io)
      import = Redirect.import_csv(file.to_io)
      Redirect.track_event(:imported, created: import.created, updated: import.updated, errored: import.errored)
      redirect_to tools_redirects_path, notice: import.summary
    else
      redirect_to tools_redirects_path, alert: "Pick a CSV file."
    end
  rescue CSV::MalformedCSVError => e
    redirect_to tools_redirects_path, alert: "CSV parse error: #{e.message}"
  end
end
