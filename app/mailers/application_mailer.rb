# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  # Outbound identity, from the install's environment. A relay like Outsend
  # only accepts mail from a domain the account owns, so the envelope sender
  # is the install's, not the site's: its own "from" settings (forms,
  # collection events) override the display name but fall back to this
  # address.
  def self.from_address
    ENV["MAIL_FROM_ADDRESS"].presence || "noreply@#{Site.host.split(":").first.presence || "localhost"}"
  end

  def self.from_name = ENV["MAIL_FROM_NAME"].presence || "Libre Publish"

  def self.default_from
    %("#{from_name}" <#{from_address}>)
  end

  default from: -> { self.class.default_from }

  # Links in mail are on this install's address (Site.host), worked out as
  # each message is made: APP_HOST, or the site's own once it's set.
  def default_url_options = super.merge(Site.url_options)
  layout "mailer"
end
