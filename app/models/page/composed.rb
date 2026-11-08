# frozen_string_literal: true

# A page's body is a list of blocks (BlockComposed).
module Page::Composed
  extend ActiveSupport::Concern
  include BlockComposed

  # The blocks with their dynamic data filled in (a collection list's
  # entries, the site's contact details), as the API serves them.
  # live: only published entries in a collection_list, whatever it says (the
  # delivery API's).
  def expanded_blocks(live: false)
    Page::BlockExpansion.new(blocks, live: live).blocks
  end
end
