# frozen_string_literal: true

# "Send a test email" on Settings › Email delivery: one email to the person
# asking, sent now, through the server saved there, so they see at once
# whether it works and, if not, what the server said.
class Settings::MailDeliveries::TestsController < Settings::BaseController
  requires_capability "settings:write", only: :create

  def create
    MailDeliveryMailer.with(to: Current.user.email).test.deliver_now
    redirect_to settings_mail_delivery_path, notice: "Sent a test email to #{Current.user.email}."
  rescue StandardError => e
    redirect_to settings_mail_delivery_path, alert: "The test email didn't send: #{e.message}"
  end
end
