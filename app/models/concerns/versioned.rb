# frozen_string_literal: true

# Every save that changes what its version class keeps (SNAPSHOT_ATTRIBUTES)
# keeps a snapshot, so an edit can be undone: a Page in PageVersion, a Global
# in GlobalVersion, and so on, by name. The including model can narrow what's
# kept (`snapshot_version?`, `version_attributes`, nil to skip one).
module Versioned
  extend ActiveSupport::Concern

  included do
    has_many :versions, class_name: "#{name}Version", dependent: :delete_all

    after_save :snapshot_version, if: :snapshot_version?
  end

  private

  def snapshot_version?
    versions.klass::SNAPSHOT_ATTRIBUTES.any? { saved_change_to_attribute?(it) }
  end

  def version_attributes
    slice(*versions.klass::SNAPSHOT_ATTRIBUTES)
  end

  def snapshot_version
    attributes = version_attributes or return
    versions.create!(**attributes.symbolize_keys, author_id: Current.user&.id, created_at: Time.current)
  end
end
