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

  LOGO_CID = "logo@cms"
  helper_method :email_logo_src, :email_site_name

  private

  # The Branding logo for this message's <img src>: the file itself, attached
  # inline and named by cid:, so it shows without the mail client fetching
  # anything (many block remote images, and drew a broken one). nil without a
  # logo a client can show. Attached the first time it's asked for, so a
  # message that doesn't draw it doesn't carry it.
  def email_logo_src
    return @email_logo_src if defined?(@email_logo_src)

    logo = Branding.current.email_logo
    @email_logo_src = if logo
      attachments.inline[logo[:filename]] = {mime_type: logo[:mime_type], content: logo[:content], content_id: "<#{LOGO_CID}>"}
      attachments[logo[:filename]].url
    end
  end

  def email_site_name = Setting.get("general")["title"].presence || Site.key
end
