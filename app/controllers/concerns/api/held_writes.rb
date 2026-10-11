# frozen_string_literal: true

# Content writes over the API with a token — the CLI, MCP, a script: the work
# an agent does — go to a plugin that holds them for a person when one is on
# (Cms::Plugins.hold_api_writes). The write isn't applied; the API answers
# 202 with what the plugin says about it (where to follow it up). A write the
# record wouldn't take is refused first (422, the errors a direct write gets),
# so nobody is asked to approve what can't be applied. A signed-in
# person's writes, and every write while no plugin holds them, apply as usual.
#
#   @page.assign_attributes(page_params)
#   return if hold_write(:update, @page, page_params, prefix: "pages")
#
# The bulk and shortcut content endpoints change many records, or one field,
# in a way nobody could review as a change, so a token is refused them
# (409) while writes are held: `refuse_while_held` before those actions.
module Api::HeldWrites
  extend ActiveSupport::Concern

  class_methods do
    def refuse_while_held(**options)
      before_action :refuse_while_held!, **options
    end
  end

  private

  # Whether the write was held, and the response rendered.
  def hold_write(action, record, attributes, prefix:)
    hold = held_writes_hold or return false
    raise ActiveRecord::RecordInvalid, record if action.to_s != "destroy" && record.invalid?

    held = hold.call(Cms::Plugins::HeldWrite.new(action: action.to_s, record: record,
      attributes: attributes.to_h.stringify_keys, prefix: prefix))
    return false if held.nil?

    render "api/held_writes/show", status: :accepted, locals: {held: held}
    true
  end

  def refuse_while_held!
    return unless held_writes_hold

    render json: {error: "held", message: "Changes from the API wait for approval, one record at a time. Write each record on its own (PATCH or DELETE it) instead."}, status: :conflict
  end

  def held_writes_hold
    Cms::Plugins.api_write_hold if Current.api_token
  end
end
