# frozen_string_literal: true

# What the page, entry and global forms share: reading the content form back
# (ContentForm) and saving it. Changing live content, or publishing or
# scheduling a draft, needs the publish capability (PublishGated); without it
# the save is refused, as in the API.
module ContentEditing
  extend ActiveSupport::Concern

  included do
    helper_method :can_publish_content?
  end

  private

  def content_block_types
    @content_block_types ||= BlockType.all.index_by(&:slug)
  end

  # An object of schema fields from params[scope][key], or `original` when
  # the form didn't post it.
  def decoded_content_object(scope, key, fields, original)
    raw = params.dig(scope, key)
    return original if raw.nil?

    ContentForm.object(fields, raw, original: original, block_types: content_block_types)
  end

  def decoded_content_blocks(scope, original)
    raw = params.dig(scope, :blocks)
    return original if raw.nil?

    ContentForm.blocks(raw, block_types: content_block_types)
  end

  # Checkbox lists post a leading "" so an emptied list still arrives.
  def content_ids(scope, key)
    ids = params.dig(scope, key)
    ids.nil? ? nil : Array(ids).compact_blank.map(&:to_i)
  end

  def content_time(scope, key)
    value = params.dig(scope, key)
    value.nil? ? :absent : value.presence
  end

  # Saves the record, or adds an error and doesn't when the write needs the
  # publish capability the user hasn't got. Whether it saved.
  #
  # The edit form posts the lock_version it was rendered with, so a save over
  # a change someone else made since is refused, with the form kept as typed.
  def save_content(record, attributes = nil, prefix:)
    record.assign_attributes(attributes) if attributes
    lock_version = posted_lock_version(record)
    record.lock_version = lock_version if lock_version
    if record.publishing_write? && !can_publish_content?(prefix)
      record.errors.add(:base, "Changing live content, or publishing, needs the publish permission")
      false
    else
      record.save
    end
  rescue ActiveRecord::StaleObjectError
    record.errors.add(:base, "Someone else saved this while you were editing, so your changes weren't saved. " \
      "Copy anything you want to keep, then reload the page to see theirs.")
    false
  end

  # The forms post under `page`, `entry` and `global`.
  def posted_lock_version(record)
    scope = record.is_a?(CollectionEntry) ? :entry : record.model_name.param_key
    value = params.dig(scope, :lock_version).to_s
    value.to_i if value.match?(/\A\d+\z/)
  end

  def can_publish_content?(prefix)
    Current.user&.can?("#{prefix}:publish")
  end
end
