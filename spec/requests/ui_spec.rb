# frozen_string_literal: true

require "rails_helper"

# Help › UI kit: every component in the site's own branding.
RSpec.describe "The UI kit", type: :request do
  it "draws rune_ui's components and the admin's own, under Docs" do
    sign_in_as create(:user, admin: false, role: create(:role, permissions: %w[pages:read]))

    get ui_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("btn btn--primary", "badge badge--ok", "alert alert--attention", "data-table",
      "rune-dialog#open", "sheet", "tabs__tab", "switch-field", "segmented", "empty")
    expect(submenu_labels("Docs")).to include("UI kit")
  end

  it "is for people signed in" do
    get ui_path

    expect(response).to redirect_to(sign_in_path)
  end
end
