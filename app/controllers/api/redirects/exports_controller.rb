# frozen_string_literal: true

# GET /api/redirects/export — every rule as CSV (Redirect::Portable).
class Api::Redirects::ExportsController < Api::BaseController
  requires_capability "redirects:read", only: :show

  def show
    send_data Redirect.to_csv, filename: Redirect.csv_filename, type: "text/csv"
  end
end
