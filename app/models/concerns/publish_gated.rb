# frozen_string_literal: true

# What the publish capability guards on a record: anything in front of
# visitors. Changing a live record, or publishing or scheduling a draft, needs
# `<resource>:publish`; without it the write is refused, not queued. The admin
# (ContentEditing) and the API (Api::PublishCapability) both ask the record,
# so the rule can't drift between them.
#
# "Live" means published for pages and entries, and simply existing for
# globals, which have no draft state.
#
#   page.assign_attributes(attributes)
#   page.publishing_write? # => true when saving needs pages:publish
module PublishGated
  extend ActiveSupport::Concern

  # Asked after the write's attributes are assigned, before saving.
  def publishing_write?
    live_in_database? || publishes_on_save?
  end

  private

  # Read from the database value, so assigning a new status first doesn't
  # change the answer.
  def live_in_database?
    respond_to?(:status) ? status_in_database.to_s == "published" : persisted?
  end

  def publishes_on_save?
    (respond_to?(:status) && status_changed? && status.to_s == "published") ||
      (respond_to?(:publish_at) && publish_at_changed? && publish_at.present?)
  end
end
