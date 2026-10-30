# frozen_string_literal: true

require "rails_helper"

# Website.render: a theme's template drawn outside a visit (a form email).
RSpec.describe Website do
  around do |example|
    registered = Website.theme
    paths = ActionController::Base.view_paths
    Website.register :fixture, name: "Fixture", version: "1", views: Rails.root.join("spec/fixtures/website_theme/views")
    example.run
  ensure
    ActionController::Base.view_paths = paths
    Website.theme = registered
  end

  # Every installed theme is an engine, and an engine puts its views on every
  # controller's path, so a theme that's installed but switched off has a
  # website/emails/form of its own there too.
  it "draws the template and its partials from the theme drawing the site, not another installed theme" do
    ActionController::Base.prepend_view_path(Rails.root.join("spec/fixtures/website_theme/other"))

    html = Website.render("website/emails/form", email: "Thanks")

    expect(html).to include(%(<p class="fixture-email">Thanks</p>), %(<p class="fixture-line">fixture line</p>))
    expect(html).not_to include("other-")
  end

  it "draws nothing the theme has no template for" do
    expect(Website.render("website/emails/missing", email: "Thanks")).to be_nil
  end
end
