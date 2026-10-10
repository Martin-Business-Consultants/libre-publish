# frozen_string_literal: true

# Run using bin/ci

CI.run do
  step "Setup", "bin/setup --skip-server"

  step "Style: Ruby", "bin/rubocop"
  step "Style: Templates", "bundle exec herb lint app/views engines"
  # A theme's templates are held to warnings too (.herb.yml): what a visitor
  # sees, accessibility included, has no "later".
  step "Style: Theme templates", "bundle exec herb lint themes --fail-level warning" if Dir.exist?("themes")

  step "Security: Gem audit", "bin/bundler-audit"
  # Bundled plugins live in engines/, which Brakeman skips unless told.
  step "Security: Brakeman code analysis", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error " \
    "--add-engines-path #{Dir["{engines,themes}/*"].join(",")}"

  step "Tests: Rails", "bin/rspec"
  # The default plugins (bin/setup installs them into plugins/) carry their
  # own specs, which run inside the CMS.
  step "Tests: Plugins", "bin/rspec plugins/*/spec"
  # A theme's spec draws every page of its site from its snapshot of the CMS.
  step "Tests: Theme", "bin/rspec themes/*/spec" if Dir["themes/*/spec"].any?
  step "Tests: Seeds", "env RAILS_ENV=test bin/rails db:seed:replant"

  # Optional: set a green GitHub commit status to unblock PR merge.
  # Requires the `gh` CLI and `gh extension install basecamp/gh-signoff`.
  # if success?
  #   step "Signoff: All systems go. Ready for merge and deploy.", "gh signoff"
  # else
  #   failure "Signoff: CI failed. Do not merge or deploy.", "Fix the issues and try again."
  # end
end
