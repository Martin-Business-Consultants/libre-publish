# frozen_string_literal: true

# Tools › SEO audit (SeoAudit): what stands between the site and search, each
# with where to fix it.
class Tools::SeoAuditsController < ApplicationController
  requires_capability "pages:read"

  def show
    @issues = SeoAudit.new.issues
  end
end
