# frozen_string_literal: true

# A copy of a live site, for working on it locally (docs/local-development.md):
# its backup (Tools › Backup, fetched by bin/pull) put in place of this
# install's database and files (TenantImport), then made safe to work on:
#
#   - nothing reaches the outside world: webhooks are switched off, the
#     deploy and GitHub settings are dropped, IndexNow is off;
#   - addresses are local: Settings › General's site URL is this machine's;
#   - you can sign in: local@localhost, password1234, an admin;
#   - without_people: every other account, form submission, session and token
#     is removed, for a copy that holds no one's personal details.
#
# Only in development: a pulled database replaces the one it lands on.
class LocalPull
  class Refused < StandardError; end

  LOCAL_EMAIL = "local@localhost"
  LOCAL_PASSWORD = "password1234"
  # Settings a local copy mustn't act on.
  OUTWARD_SETTINGS = %w[deploy github].freeze
  # Tables of what people sent in, cleared without_people (a plugin's, when it's installed).
  PEOPLE_TABLES = %w[form_submissions quote_requests].freeze

  attr_reader :report

  def initialize(archive, without_people: false, local_url: "http://localhost:3000", out: $stdout)
    @archive = archive
    @without_people = without_people
    @local_url = local_url
    @out = out
    @report = {}
  end

  def call
    raise Refused, "A pull replaces this install's database, so it only runs in development (this is #{Rails.env})." unless Rails.env.development? || ENV["CMS_ALLOW_PULL"] == "1"

    TenantImport.new(@archive, force: true, out: @out, local: true).call
    [ActiveRecord::Base, *ActiveRecord::Base.descendants].each { it.reset_column_information if it.respond_to?(:reset_column_information) }
    localize
    @report
  end

  private

  def localize
    general = Setting.get("general")
    @report[:site_url] = general["site_base_url"]
    Setting.set("general", {"site_base_url" => @local_url})

    @report[:webhooks_off] = Webhook.where(active: true).update_all(active: false)
    OUTWARD_SETTINGS.each { Setting.delete_key(it) }
    Setting.set(SearchSettings::SETTING_KEY, {"indexnow" => false})

    Session.delete_all
    forget_people if @without_people
    @report[:sign_in] = local_admin
    say "Signed in as #{LOCAL_EMAIL} / #{LOCAL_PASSWORD} (an admin). The site's own accounts #{@without_people ? "were removed" : "work too"}."
    say "Webhooks off (#{@report[:webhooks_off]}), deploys and IndexNow off, and the site's address is #{@local_url} (it was #{@report[:site_url].presence || "unset"})."
  end

  def forget_people
    connection = ActiveRecord::Base.connection
    PEOPLE_TABLES.each { connection.execute("DELETE FROM #{connection.quote_table_name(it)}") if connection.table_exists?(it) }
    ApiToken.delete_all if defined?(ApiToken)
    User.where.not(email: LOCAL_EMAIL).find_each { it.destroy }
    @report[:people_removed] = true
  end

  def local_admin
    user = User.find_or_initialize_by(email: LOCAL_EMAIL)
    user.assign_attributes(name: "Local", password: LOCAL_PASSWORD, verified: true, role: Role.system_admin)
    user.save!
    LOCAL_EMAIL
  end

  def say(line) = @out.puts(line)
end
