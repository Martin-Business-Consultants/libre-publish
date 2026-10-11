# frozen_string_literal: true

# The email sender was in two places, Settings › General and Settings ›
# Forms; it's Forms' alone now. A sender saved in General moves over where
# Forms has none.
class MoveEmailSenderToForms < ActiveRecord::Migration[8.1]
  class Setting < ActiveRecord::Base
    self.table_name = "settings"
  end

  def up
    general = Setting.find_by(key: "general") or return
    data = general.data.to_h
    moved = {"from_name" => data["email_from_name"], "from_email" => data["email_from_address"]}.compact_blank
    return if moved.empty?

    forms = Setting.find_or_initialize_by(key: "forms_settings")
    forms.data = moved.merge(forms.data.to_h.compact_blank)
    forms.save!
    general.update!(data: data.except("email_from_name", "email_from_address"))
  end

  def down
  end
end
