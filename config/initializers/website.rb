# frozen_string_literal: true

# The website's catch-all comes last, after every route a plugin appends
# (registered once every initializer has run), so it never hides one. What no
# other route answers, the website looks up (Website::PagesController) and
# themes a 404 for, and an address the admin had before /cms goes there; with
# no theme, only the second, and anything else is the plain 404. The API,
# Active Storage and assets answer their own unknown paths. "/" is in
# config/routes.rb.
Rails.application.config.after_initialize do |app|
  app.routes.append do
    get "*path", to: "website/pages#show", format: false, as: :website_page,
      constraints: ->(request) { !request.path.start_with?("/api/", "/rails/", "/assets/") }
  end
end
