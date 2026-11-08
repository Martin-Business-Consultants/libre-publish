# frozen_string_literal: true

# PATCH /api/collections/:collection/entries/:slug/move — the Build board's
# drag over the API: `{"on": true}` moves the entry to the right-hand column,
# which means everything that column stands for (CollectionEntry::Boardable).
# `false` mirrors it back off.
class Api::Collections::Entries::PlacementsController < Api::BaseController
  include EntryScoped
  include Api::HeldWrites

  requires_capability "entries:write", only: :update
  refuse_while_held only: :update

  def update
    unless @collection.build_board?
      return render json: {error: "invalid", message: "#{@collection.slug} has no Build board — set build_config.field on its schema first"},
        status: :unprocessable_content
    end
    # A column that publishes takes publishing the entry.
    require_capability!("entries:publish") if @collection.build_publishes?

    @entry.place_on_board!(ActiveModel::Type::Boolean.new.cast(params[:on]))
    render "api/collection_entries/show"
  end
end
