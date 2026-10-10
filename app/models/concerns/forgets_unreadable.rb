# frozen_string_literal: true

# For a record with an encrypted attribute this install's keys can't read (a
# site moved from another install without its keys): saving a new value
# reads the old one to see what changed, and that raises. So the unreadable
# value is cleared in the table first, and the save carries on as for a
# record that never had one.
#
#   def rotate!
#     forget_unreadable(:token)
#     update!(token: ...)
#   end
#
# Clearing it is never quiet: the same keys that can't read it might only be
# misconfigured (a key rotated without keeping the previous one), so the
# ciphertext goes into the audit log first ("<model>.unreadable_value_cleared",
# with the attribute), from where the right keys can still decrypt it, and
# the log says so as an error.
module ForgetsUnreadable
  extend ActiveSupport::Concern

  def forget_unreadable(attribute)
    public_send(attribute)
  rescue ActiveRecord::Encryption::Errors::Decryption
    ciphertext = ciphertext_for(attribute)
    track_event(:unreadable_value_cleared, attribute: attribute.to_s, ciphertext: ciphertext)
    Rails.logger.error("[ForgetsUnreadable] #{self.class.name}##{id} #{attribute}: this install's encryption keys can't read it; " \
      "cleared, ciphertext kept in the audit log")
    self.class.where(id: id).update_all(attribute => nil)
    reload
  end
end
