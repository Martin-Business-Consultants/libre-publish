# frozen_string_literal: true

# POST /api/frontend/builds — the site's build telling the CMS it ran
# (@librepublish/astro's cms() integration): the integration's and Astro's versions, how
# many pages it built, how it renders (`render`: static, server or hybrid),
# where it takes cache purges (`webhook_url`), and the content it was built
# from (`content_cursor`, opaque). The CMS keeps the latest (Frontend): the
# Developers screen and the dashboard say which frontend it serves, and
# Deploys rebuilds a static site but purges one rendered on demand. Any token
# the site builds with (pages:read) may send it.
#
# How the site renders and where purges go only take effect when they keep
# it rebuilt on publish, or once someone who can change Settings › Deploy
# approves them (Frontend.record_build); a report sent with settings:write
# is that approval.
class Api::Frontend::BuildsController < Api::BaseController
  enforce_authorization
  requires_capability "pages:read", only: :create

  def create
    @build = Frontend.record_build(params.permit(:integration, :integration_version, :framework, :framework_version,
      :pages, :site_url, :duration_ms, :render, :webhook_url, :content_cursor).to_h)
    Frontend.approve_delivery! if granted?("settings:write")
    @pending = Frontend.pending_delivery
  end
end
