# frozen_string_literal: true

# POST /api/globals/bulk_destroy: the globals at `slugs` to the trash
# (Global.trash_all).
class Api::Globals::BulkDeletionsController < Api::BaseController
  include Api::BulkSlugs
  include Api::HeldWrites

  enforce_authorization
  requires_capability "globals:delete", only: :create
  refuse_while_held only: :create

  def create
    @globals = Global.trash_all(Global.where(slug: bulk_slugs).to_a)
    @not_found = missing_slugs(@globals)
  end
end
