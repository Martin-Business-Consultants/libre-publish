# frozen_string_literal: true

# Every encrypted value in the database (API and service tokens, settings'
# secrets), rewritten with this install's keys: run once a site moved here
# reads its old values (CMS_PREVIOUS_SECRET_KEY_BASE,
# config/initializers/active_record_encryption.rb), and the previous key can
# go. A value no key here can read is left as it is and counted.
#
#   EncryptedValues.reencrypt   # => {rewritten: 3, unreadable: 0}
module EncryptedValues
  extend self

  def models
    Rails.application.eager_load!
    ActiveRecord::Base.descendants.reject(&:abstract_class?).select { it.encrypted_attributes.present? && it.table_exists? }
  end

  def reencrypt
    models.each_with_object(Hash.new(0)) do |model, tally|
      scope = model.respond_to?(:with_discarded) ? model.with_discarded : model.unscoped
      scope.find_each do |record|
        model.encrypted_attributes.each { record.public_send(it) } # raises when no key here reads it
        record.encrypt
        tally[:rewritten] += 1
      rescue ActiveRecord::Encryption::Errors::Decryption
        tally[:unreadable] += 1
      end
    end
  end
end
