# frozen_string_literal: true

# Settings › Email delivery: the SMTP server the CMS sends email through
# (MailDelivery). A blank password keeps the one saved; the page never shows
# it. Emptying the host goes back to the install's own server.
class Settings::MailDeliveriesController < Settings::BaseController
  requires_capability "settings:read",  only: :show
  requires_capability "settings:write", only: :update

  def show
    @settings = MailDelivery::FIELDS.index_with { MailDelivery.settings[it].to_s }
    @settings["security"] = "starttls" if @settings["security"].blank?
    @password_set = MailDelivery.password.present?
  end

  def update
    attrs = params.require(:mail_delivery).permit(*MailDelivery::FIELDS, :password).to_h
    password = attrs.delete("password").to_s
    Setting.set(MailDelivery::KEY, attrs)
    Setting.set_secret(MailDelivery::KEY, password: password) if password.strip.present?
    Setting.unset(MailDelivery::KEY, "password")
    Event.record("settings.mail_delivery_updated", fields: attrs.keys + (password.present? ? ["password"] : []))
    redirect_to settings_mail_delivery_path, notice: "Email delivery saved"
  end
end
