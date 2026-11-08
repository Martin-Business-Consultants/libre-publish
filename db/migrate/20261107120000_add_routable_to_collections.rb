# frozen_string_literal: true

# Whether a collection's entries have pages of their own. Posts do; a list of
# testimonials or partners is data a block draws, with no page per entry. A
# frontend needs a template for each routable collection (the Astro
# integration's contract), and the sitemap lists only routable entries.
class AddRoutableToCollections < ActiveRecord::Migration[8.1]
  def change
    add_column :collections, :routable, :boolean, default: true, null: false, if_not_exists: true
  end
end
