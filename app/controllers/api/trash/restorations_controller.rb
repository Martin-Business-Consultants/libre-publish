# frozen_string_literal: true

# POST /api/trash/:kind/:id/restore
class Api::Trash::RestorationsController < Api::BaseController
  include Api::TrashScoped

  enforce_authorization
  requires_capability "trash:write", only: [:create]

  # A restore puts content back: while a plugin holds API writes for a person
  # (Approvals), it's done in the admin. A global has no draft to come back
  # as, so it's live at once, and takes publishing one.
  include Api::HeldWrites
  refuse_while_held only: :create

  def create
    require_capability!("globals:publish") if @record.is_a?(Global)
    capability = Trash.publish_capability(@record)
    Trash.restore(params[:kind], @record, as_draft: capability.present? && !granted?(capability))
    @record.reload
  end
end
