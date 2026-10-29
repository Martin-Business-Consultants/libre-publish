# frozen_string_literal: true

# "Send a test email" on Settings › Email delivery: one email to the person
# asking, sent now, through the server saved there, so they see at once
# whether it works and, if not, what the server said. Capped well under the
# proxy's own timeout, so a server that never answers (a blocked port, the
# wrong encryption for it) gets a reason on the page instead of a spinner.
class Settings::MailDeliveries::TestsController < Settings::BaseController
  LIMIT = 20.seconds

  requires_capability "settings:write", only: :create

  def create
    Timeout.timeout(LIMIT) { MailDeliveryMailer.with(to: Current.user.email).test.deliver_now }
    redirect_to settings_mail_delivery_path, notice: "Sent a test email to #{Current.user.email}."
  rescue Timeout::Error
    redirect_to settings_mail_delivery_path, alert: "The test email didn't send: #{server} didn't answer within " \
      "#{LIMIT.inspect}. Check the port and encryption match, and that this server can reach that port."
  rescue StandardError => e
    redirect_to settings_mail_delivery_path, alert: "The test email didn't send: #{e.message} (#{server})"
  end

  private

  def server
    options = MailDelivery.configured? ? MailDelivery.smtp_options : ActionMailer::Base.smtp_settings
    "#{options[:address]}:#{options[:port]}"
  end
end
