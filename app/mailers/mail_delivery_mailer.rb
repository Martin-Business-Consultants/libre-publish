# frozen_string_literal: true

# Settings › Email delivery's test email.
class MailDeliveryMailer < ApplicationMailer
  def test
    @server = MailDelivery.configured? ? MailDelivery.settings["address"] : "the install's default server"
    mail to: params[:to], subject: "Test email from #{email_site_name}"
  end
end
