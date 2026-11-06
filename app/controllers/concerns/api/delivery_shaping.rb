# frozen_string_literal: true

# What a site asks of a delivery answer (/api/v1) beside the records, as the
# Go core answers it (docs/delivery-api.md):
#
#   ?fields=title,slug,seo.meta_title   only those keys (and id) of each record
#   ?include=assets,entries,pages       what goes in `included`: the assets the
#                                       records point at (the default), the live
#                                       entries and pages they link to, or none
#
# and how many a list holds, in headers: X-Total-Count, X-Total-Pages and a
# Link with first, prev, next and last.
#
# `fields` is applied after the fact, to what the view rendered, the way the
# agent envelope is (Api::AgentEnvelope): every record's shape stays in its
# one partial.
module Api::DeliveryShaping
  extend ActiveSupport::Concern

  included do
    after_action :keep_asked_fields, if: -> { params[:fields].present? && response.successful? && response.media_type == "application/json" }
    helper_method :included?
  end

  private

  # Whether `included` should carry what (assets, entries, pages).
  def included?(what)
    asked = params[:include].to_s.split(",").map(&:strip).compact_blank
    asked = ["assets"] if asked.empty?
    asked.include?(what.to_s)
  end

  def paging_headers(page, per, total)
    pages = [(total + per - 1) / per, 1].max
    response.headers["X-Total-Count"] = total.to_s
    response.headers["X-Total-Pages"] = pages.to_s
    links = [[1, "first"]]
    links << [page - 1, "prev"] if page > 1
    links << [page + 1, "next"] if page < pages
    links << [pages, "last"]
    response.headers["Link"] = links.map { |number, rel|
      %(<#{request.base_url}#{request.path}?#{request.query_parameters.merge("page" => number.to_s, "per" => per.to_s).to_query}>; rel="#{rel}")
    }.join(", ")
  end

  # Each record of `data` cut to the asked-for keys, `id` always: top-level
  # names, or dot paths into objects (seo.meta_title → {"seo" => {"meta_title" => …}}).
  def keep_asked_fields
    paths = params[:fields].to_s.split(",").map(&:strip).compact_blank.map { it.split(".") }
    body = JSON.parse(response.body)
    data = body["data"]
    body["data"] = data.is_a?(Array) ? data.map { picked(it, paths) } : picked(data, paths)
    response.body = JSON.generate(body)
  rescue JSON::ParserError
    nil
  end

  def picked(record, paths)
    return record unless record.is_a?(Hash)

    paths.each_with_object({"id" => record["id"]}) do |path, out|
      next if path == ["id"]

      parent = path[0...-1].reduce(record) { |node, key| node.is_a?(Hash) ? node[key] : nil }
      next unless parent.is_a?(Hash) && parent.key?(path.last)

      target = path[0...-1].reduce(out) { |node, key| node[key] = node[key].is_a?(Hash) ? node[key] : {} }
      target[path.last] = parent[path.last]
    end
  end
end
