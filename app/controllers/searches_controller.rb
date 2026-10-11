# frozen_string_literal: true

# The admin bar's search (GlobalSearch): everything the person can read that
# holds the term, a page at a time. ?quick=1 is the search modal's results as
# you type (GlobalSearch::Quick, searches/_quick), without the layout.
class SearchesController < ApplicationController
  # Signed in, and no one capability: it finds only the kinds of record the
  # person's role can read (GlobalSearch::KINDS).
  skip_authorization

  def show
    if params[:quick].present?
      return render partial: "quick", locals: {quick: GlobalSearch::Quick.new(params[:q], user: Current.user)}
    end

    @search = GlobalSearch.new(params[:q], user: Current.user)
    @results = paginate(@search)
  end
end
