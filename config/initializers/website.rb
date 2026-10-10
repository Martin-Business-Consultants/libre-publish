# frozen_string_literal: true

# The website's catch-all comes last, after every route a plugin appends
# (registered once every initializer has run), so it never hides one: what
# no other route answers, the website looks up (Website::PagesController),
# and themes a 404 for. With no theme it isn't there, and an unknown path is
# a plain 404 as before. The API answers its own unknown paths (JSON), and
# Active Storage and assets their own. "/" is in config/routes.rb.
Rails.application.config.after_initialize do |app|
  app.routes.append do
    get "*path", to: "website/pages#show", format: false, as: :website_page,
      constraints: ->(request) { Website.enabled? && !request.path.start_with?("/api/", "/rails/", "/assets/") }
  end
end
