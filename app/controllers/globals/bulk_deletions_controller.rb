# frozen_string_literal: true

# Content › Globals: the ticked globals to the trash in one go.
class Globals::BulkDeletionsController < ApplicationController
  include BulkSlugs

  requires_capability "globals:delete", only: :create

  def create
    globals = Global.trash_all(Global.where(slug: bulk_slugs).to_a)
    redirect_to globals_path, notice: "#{globals.size} #{"global".pluralize(globals.size)} moved to trash"
  end
end
