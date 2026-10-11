# frozen_string_literal: true

# How the CMS sends email (Settings › Email delivery): an SMTP server of the
# site's own — host, port, encryption, sign-in — in place of the install's
# (SMTP_* in its environment, Outsend's relay by default). Stored in the
# `mail_delivery` setting; the password in its encrypted secrets, never shown
# again. Every email the CMS and its plugins send goes through it once a host
# is set (ApplicationMailer#mail). Who mail comes from is Settings › Forms'.
class MailDelivery
  KEY = "mail_delivery"
  FIELDS = %w[address port security user_name authentication].freeze
  SECURITY = {"starttls" => "STARTTLS (usually port 587)", "ssl" => "SSL/TLS (usually port 465)", "none" => "None (usually port 25)"}.freeze
  PORTS = {"starttls" => 587, "ssl" => 465, "none" => 25}.freeze
  AUTHENTICATIONS = {"plain" => "Plain", "login" => "Login", "cram_md5" => "CRAM-MD5"}.freeze

  def self.settings = Setting.get(KEY)

  def self.configured? = settings["address"].present?

  def self.password = Setting.secret(KEY, "password")

  # Action Mailer's smtp settings for the server set here.
  def self.smtp_options
    data = settings
    security = data["security"].presence_in(SECURITY.keys) || "starttls"
    options = {address: data["address"].to_s.strip, port: (data["port"].presence || PORTS[security]).to_i, open_timeout: 5, read_timeout: 10}
    if data["user_name"].present?
      options.merge!(user_name: data["user_name"].to_s.strip, password: password,
        authentication: (data["authentication"].presence_in(AUTHENTICATIONS.keys) || "plain").to_sym)
    end
    case security
    when "ssl" then options[:tls] = true
    when "starttls" then options[:enable_starttls] = true
    else options[:enable_starttls_auto] = false
    end
    options
  end
end
