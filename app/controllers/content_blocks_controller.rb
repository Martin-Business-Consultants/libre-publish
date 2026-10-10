# frozen_string_literal: true

# GET /content_blocks/new?type=hero&scope=page[blocks]&depth=1 — one new block
# row for a content form's "Add block" picker: a fresh id, the type's current
# version and its defaults, named to join the list at `scope`.
class ContentBlocksController < ApplicationController
  WRITE_CAPABILITIES = %w[pages:write entries:write globals:write].freeze
  SCOPE = /\A[a-z_]+(\[[A-Za-z0-9_]+\])*\z/

  skip_authorization
  before_action :require_content_write

  def new
    scope = params[:scope].to_s
    return head(:bad_request) unless scope.match?(SCOPE)
    return new_pattern(params[:type].to_s.delete_prefix("pattern:"), scope) if params[:type].to_s.start_with?("pattern:")

    block_type = BlockType.find_by!(slug: params[:type].to_s)

    block = {"id" => SecureRandom.uuid, "type" => block_type.slug, "version" => block_type.version,
             "data" => block_type.defaults.is_a?(Hash) ? block_type.defaults.deep_dup : {}}
    render partial: "content_form/block", locals: {
      block: block, scope: helpers.content_scope(scope)[helpers.content_row_key],
      depth: params[:depth].to_i, errors: [], open: true
    }
  end

  private

  # A pattern from the picker's Patterns section: a synced one as one
  # "pattern" block naming it, an unsynced one as copies of its blocks.
  def new_pattern(slug, scope)
    pattern = BlockPattern.find_by!(slug: slug)
    blocks = if pattern.synced?
      [{"id" => SecureRandom.uuid, "type" => "pattern", "version" => BlockType.find_by(slug: "pattern")&.version || 1, "data" => {"pattern" => pattern.slug}}]
    else
      pattern.copied_blocks
    end
    rows = blocks.map do |block|
      render_to_string(partial: "content_form/block", locals: {
        block: block, scope: helpers.content_scope(scope)[helpers.content_row_key], depth: params[:depth].to_i, errors: [], open: true
      })
    end
    render html: rows.join.html_safe # rubocop:disable Rails/OutputSafety -- our own rendered partials
  end

  # Adding a block is part of writing a page, entry or global, whichever
  # this form is.
  def require_content_write
    head :forbidden unless WRITE_CAPABILITIES.any? { Current.user&.can?(it) }
  end
end
