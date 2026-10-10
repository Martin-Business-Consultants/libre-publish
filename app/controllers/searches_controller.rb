# frozen_string_literal: true

# The admin bar's search (GlobalSearch): everything the person can read that
# holds the term, a page at a time.
class SearchesController < ApplicationController
  # Signed in, and no one capability: it finds only the kinds of record the
  # person's role can read (GlobalSearch::KINDS).
  skip_authorization

  def show
    @search = GlobalSearch.new(params[:q], user: Current.user)
    @results = paginate(@search)
  end
end
