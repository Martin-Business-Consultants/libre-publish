# frozen_string_literal: true

# Numbered pagination for index tables (Pagination, layouts/shared/_pagination).
module PaginationHelper
  # url_for treats these keys as URL-generation control options rather than
  # query parameters. Forwarding them from untrusted request params lets an
  # attacker rewrite the generated pagination path — both `script_name` and
  # `original_script_name` are prepended to the generated script name by
  # RouteSet#url_for before route generation, so either can retarget the link
  # onto an arbitrary same-origin route such as an Active Storage blob-proxy
  # path (HackerOne #3943339). These are the RESERVED_OPTIONS url_for strips
  # before route generation, plus the two control keys it deletes outside that
  # list (_recall, relative_url_root). We forward path parameters
  # (controller/action and route segments like board_id) untouched so url_for
  # can regenerate the current parameterized route; only these control keys are
  # stripped.
  URL_FOR_CONTROL_OPTIONS = %i[
    script_name original_script_name host protocol port subdomain domain
    tld_length trailing_slash only_path relative_url_root anchor params
    _recall
  ].freeze

  # The numbered pagination under an index table (Pagination): « Previous,
  # the page numbers with gaps, Next », and which rows these are. Nothing when
  # the list fits on one page.
  #
  #   <%= pagination_nav @pagination %>
  def pagination_nav(pagination)
    render "layouts/shared/pagination", pagination: pagination if pagination&.many?
  end

  # This page's URL at another page number: its filters and search kept,
  # page 1 without a page parameter.
  def pagination_path(number)
    url_for(forwardable_request_params.except(:page).merge(number > 1 ? {page: number} : {}))
  end

  # For plugins written when index tables loaded more rows as they scrolled:
  # each draws the numbered pagination where the "load more" link was.
  def table_next_page_row(_name, page, columns:)
    return unless page.respond_to?(:many?) && page.many?

    tag.tr { tag.td(pagination_nav(page), colspan: columns, class: "px-3") }
  end

  def pagination_frame_id_for(namespace, page_number)
    "#{namespace}-pagination-contents-#{page_number}"
  end

  def with_automatic_pagination(_name, page, **)
    safe_join([capture { yield }, pagination_nav(page)])
  end
  alias_method :with_manual_pagination, :with_automatic_pagination

  # A table with no rows: one quiet line across every column, in their place,
  # and (link:) a way back when a filter or search left it empty — never
  # buttons; the page header has the list's actions.
  #
  #   <%= table_empty_row "No pages yet.", columns: 5 if @pages.none? %>
  #   <%= table_empty_row "No pages match.", columns: 5, link: ["Show all", pages_path] %>
  def table_empty_row(message, columns:, link: nil)
    tag.tr do
      tag.td colspan: columns, class: "px-3 py-12 text-center text-sm text-gray-500" do
        safe_join([message, (link_to(link.first, link.last, class: ui(:link)) if link)].compact, " ")
      end
    end
  end

  private

  # The route's own parameters (controller, action, ids) and the query string —
  # what the next page's link needs — rather than `params.permit!`, which would
  # also carry any request body.
  def forwardable_request_params
    request.path_parameters.merge(request.query_parameters).symbolize_keys.except(*URL_FOR_CONTROL_OPTIONS)
  end
end
