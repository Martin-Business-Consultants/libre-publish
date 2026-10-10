# frozen_string_literal: true

# Tools › Search and replace (SearchReplace): find a phrase across the site's
# content and see every record it's in; then replace it everywhere, which
# changes live content, so it takes the publish capabilities.
class Tools::SearchReplacesController < ApplicationController
  requires_capability "pages:read", only: :show
  requires_capability "pages:write", only: :create

  def show
    @search = SearchReplace.new(params[:term], params[:replacement], case_sensitive: params[:case_sensitive] == "1")
    @matches = @search.valid? ? @search.matches : []
  end

  def create
    unless %w[pages:publish entries:publish globals:publish].all? { Current.user.can?(it) }
      return redirect_to(tools_search_replace_path, alert: "Replacing changes live pages, entries and globals, so it needs the publish permissions.")
    end

    search = SearchReplace.new(params[:term], params[:replacement], case_sensitive: params[:case_sensitive] == "1")
    return redirect_to(tools_search_replace_path, alert: "Search for at least #{SearchReplace::MIN_LENGTH} characters.") unless search.valid?

    result = search.replace!
    notice = "Replaced #{helpers.pluralize(result[:replaced], "match")} in #{helpers.pluralize(result[:records], "record")}."
    notice += " #{result[:failed].size} couldn’t be saved: #{result[:failed].map { |record, error| "#{record.title.presence || record.try(:name)} (#{error})" }.to_sentence}." if result[:failed].any?
    redirect_to tools_search_replace_path(term: params[:replacement].presence || params[:term]), notice: notice
  end
end
