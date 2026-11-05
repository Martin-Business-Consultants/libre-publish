# frozen_string_literal: true

require "rails_helper"

# A real backup from the Go core (spec/fixtures/go_backups/site.tar.gz, made
# by script/go_backup_fixture with librepublishgo v2.10): two pages of
# rich-text hero blocks, a collection with two entries, a footer global with
# rich text in a repeater, an uploaded image linked from the rich text, a
# webhook with its secret, service tokens, a form with a submission, a second
# person on a role with a Go plugin's capabilities, and settings with sealed
# secrets. secret.key beside it is that install's key. The import runs into a
# throwaway database with this install's schema, never the test one.
RSpec.describe GoImport do
  self.use_transactional_tests = false

  let(:dir) { Pathname(Dir.mktmpdir("go-import")) }
  let(:target) { dir.join("install.sqlite3") }
  let(:fixtures) { Rails.root.join("spec/fixtures/go_backups") }
  let(:backup) { fixtures.join("site.tar.gz") }
  let(:secret_key) { fixtures.join("secret.key").read }
  let(:out) { StringIO.new }
  let(:image) { "pixel.png" }

  before do
    on_database(target) do
      ActiveRecord::Schema.verbose = false
      load Rails.root.join("db/schema.rb")
    end
  end

  after do
    on_database(target) { ActiveStorage::Blob.pluck(:key) if ActiveRecord::Base.connection.table_exists?("active_storage_blobs") }
      .to_a.each { FileUtils.rm_f(ActiveStorage::Blob.service.path_for(it)) }
    FileUtils.rm_rf(dir)
  end

  def on_database(path)
    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: path.to_s)
    ActiveRecord::Base.descendants.each(&:reset_column_information)
    yield
  ensure
    ActiveRecord::Base.establish_connection(:test)
    ActiveRecord::Base.descendants.each(&:reset_column_information)
  end

  def import(source = backup, **options)
    on_database(target) do
      result = described_class.new(source, out:, **options).call
      yield if block_given?
      result
    end
  end

  def query(sql) = ActiveRecord::Base.connection.select_rows(sql)

  # The fixture again, with entries added.
  def repacked(extra)
    dir.join("repacked.tar.gz").tap do |path|
      File.open(path, "wb") do |file|
        Zlib::GzipWriter.wrap(file) do |gz|
          Gem::Package::TarWriter.new(gz) do |tar|
            GoImport::Archive.each_header(backup) do |name, entry|
              body = entry.read.to_s
              tar.add_file_simple(name, 0o600, body.bytesize) { it.write(body) }
            end
            extra.each { |name, body| tar.add_file_simple(name, 0o600, body.bytesize) { it.write(body) } }
          end
        end
      end
    end
  end

  it "moves the Go site over: people, content as this core keeps it, files, secrets and forms" do
    import(secret_keys: [secret_key]) do
      owner = User.find_by(email: "owner@example.test")
      expect(owner.authenticate("correct horse battery staple")).to be_truthy
      expect(owner.role).to eq(Role.system_admin)
      clerk = User.find_by(email: "clerk@example.test")
      expect(clerk.authenticate("another long password 42")).to be_truthy
      # forms:read and forms:write are kept where the Forms plugin is installed.
      expect(clerk.role).to have_attributes(name: "Forms clerk", permissions: ["pages:read", "forms:read", "forms:write"].select { Permissions.known?(it) })
      expect(Role.all).to all(be_valid)

      hero = BlockType.find_by(slug: "hero")
      expect(hero.fields.map { it["type"] }).to eq(%w[string text asset])
      expect(Collection.find_by(slug: "posts").schema["fields"].map { it["type"] }).to eq(%w[text text asset])

      home = Page.find_by(path: "home")
      expect(home).to be_valid
      expect(home.status).to eq("published")
      body = home.blocks.first["data"]["body"]
      blob = ActiveStorage::Blob.find_by(filename: image)
      expect(body).to start_with("<h2>Welcome &amp; hello</h2><p>We are <strong>bold</strong> and <em><a href=\"http://")
      expect(body).to include(Rails.application.routes.url_helpers.rails_blob_path(blob, only_path: true), "<code>x &lt; y</code>",
        %(<ol start="3">), %(<input type="checkbox" checked="" disabled="">), %(<pre><code class="language-ruby">puts 1 &lt; 2</code></pre>))
      expect(body).not_to include("/files/")
      expect(home.blocks.first["data"]["image"]).to eq(Asset.first.id.to_s)
      expect(PageVersion.where(page: home).first.blocks.first["data"]["body"]).to eq(body)
      expect(Page.find_by(path: "about")).to have_attributes(status: "draft", seo: {"description" => "Who we are", "title" => "About"})

      entry = CollectionEntry.find_by(slug: "first-post")
      expect(entry).to be_valid
      expect(entry.frontmatter).to eq("content" => "<p>Entry rich text</p>", "cover" => Asset.first.id.to_s, "summary" => "A summary")
      expect(entry.body_markdown).to eq("Some **markdown** body.")
      expect(Global.find_by(slug: "footer").data).to eq("blurb" => "<p>Footer blurb</p>", "tagline" => "Made with care",
        "links" => [{"label" => "Home", "note" => "<p><strong>Nested</strong></p>"}])
      expect(Global.find_by(slug: "footer")).to be_valid

      asset = Asset.first
      expect(asset).to have_attributes(alt: "An orange square", folder: "/images", filename: image)
      expect(blob.service_name).to eq(ActiveStorage::Blob.service.name.to_s)
      expect(Digest::MD5.base64digest(blob.download)).to eq(blob.checksum)
      expect(Redirect.pluck(:source_path, :destination_url)).to eq([["/old", "/home"]])

      expect(Webhook.first.secret).to eq("whsec_go_fixture_secret_1234")
      production = ServiceToken.find_by(name: "PRODUCTION")
      expect(production.token).to start_with("lps_")
      expect(ServiceToken.authenticate(production.token)).to eq(production)
      expect(production.role.name).to eq("Production site")
      expect(query("SELECT token FROM service_tokens").flatten).to all(start_with("{"))
      expect(Setting.get("github")).to eq("frontend_github_repo" => "acme/site", "token" => "ghp_fixture_token_9876")
      expect(MailDelivery.settings).to include("address" => "smtp.example.test", "port" => 587, "security" => "starttls", "user_name" => "mailer")
      expect(MailDelivery.password).to eq("smtp-pass-123")
      expect(Setting.get("email")).not_to have_key("smtp_password")

      expect(query("SELECT slug, title, status, submit_label FROM forms")).to eq([["contact", "Contact", "published", "Send it"]])
      expect(JSON.parse(query("SELECT fields FROM forms").first.first)).to eq([
        {"name" => "name", "label" => "Your name", "type" => "text", "required" => true},
        {"name" => "email", "label" => "Email", "type" => "email", "required" => true},
        {"name" => "message", "label" => "Message", "type" => "textarea"},
        {"name" => "topic", "label" => "Topic", "type" => "select", "options" => [{"value" => "Sales", "label" => "Sales"}, {"value" => "Support", "label" => "Support"}]}
      ])
      expect(query("SELECT kind, recipients, subject, enabled FROM form_emails")).to eq([["notification", "owner@example.test", "New {{form_title}} submission", 1]])
      blocks = JSON.parse(query("SELECT blocks FROM form_emails").first.first)
      expect(blocks.map { [it["type"], it["data"]] }).to eq([["email_text", {"body" => "<p>From {{name}}</p>"}],
        ["email_submission", {"title" => "Submission details", "skip_empty" => false}]])
      data, meta = query("SELECT data, meta FROM form_submissions").first.map { JSON.parse(it) }
      expect(data).to eq("email" => "ada@example.test", "message" => "Hello there", "name" => "Ada Lovelace", "topic" => "Sales")
      expect(meta).to include("status" => "new")
      if defined?(Form) # the Forms plugin, installed (bin/setup puts it in plugins/)
        form = Form.find_by(slug: "contact")
        expect(form).to be_valid
        expect(form.emails.map(&:kind)).to eq(["notification"])
        expect(form.emails).to all(be_valid)
        expect(form.submissions.count).to eq(1)
      end

      expect(Session.count).to eq(0)
      expect(RecordDocument.where(record_type: "Page").count).to eq(2)
      expect(AuditLog.order(:id).last).to have_attributes(action: "site_backup.imported", actor_label: "system")
      expect(AuditLog.order(:id).last.metadata).to include("format" => "librepublish-go", "secrets" => {"total" => 5, "carried" => 5})
      expect(query("SELECT seq FROM sqlite_sequence WHERE name = 'users'").first.first).to eq(2)
    end

    expect(out.string).to include("files: 1 whole", "secrets: 5 sealed, 5 carried", "4 rich text fields", "forms: 1 forms, 1 emails, 1 submissions",
      "owners: owner@example.test", "Done.")
  end

  it "clears the secrets it can't open without the old key, and says so" do
    import do
      expect(ServiceToken.pluck(:token)).to all(be_nil)
      expect(ServiceToken.pluck(:token_digest)).to all(be_present)
      expect(Webhook.first.secret).to be_present.and(satisfy { !it.start_with?("go1:") && it != "whsec_go_fixture_secret_1234" })
      expect(Setting.get("github")).to eq("frontend_github_repo" => "acme/site")
      expect(MailDelivery.password).to be_nil
    end

    expect(out.string).to include("secrets: 5 sealed, 0 carried, cleared:", "service_tokens.token × 2", "a webhook's signing secret couldn't be opened",
      "give its secret.key with SECRET_KEY_FILE")
  end

  it "carries the secrets with the key the backup holds" do
    import(repacked("secret.key" => secret_key)) do
      expect(Webhook.first.secret).to eq("whsec_go_fixture_secret_1234")
    end
  end

  it "refuses a key that opens none of the secrets, changing nothing" do
    expect { import(secret_keys: ["not the key"]) }.to raise_error(described_class::Error, /doesn't open the backup's sealed values/)
    expect(on_database(target) { Page.count }).to eq(0)
  end

  it "changes nothing on a dry run" do
    import(dry_run: true, secret_keys: [secret_key])

    expect(on_database(target) { [User.count, Page.count, AuditLog.count] }).to eq([0, 0, 0])
    expect(dir.glob("install.sqlite3.before-import-*")).to be_empty
    expect(out.string).to include("(dry run)", "records: roles 6, users 2", "files: 1 whole", "Nothing was changed.")
  end

  it "refuses a site with people unless forced, keeping the one it replaces" do
    on_database(target) { create(:user, email: "here@example.test") }

    expect { import }.to raise_error(described_class::Error, /already has users/)
    expect(on_database(target) { User.pluck(:email) }).to eq(["here@example.test"])

    import(force: true) { expect(User.pluck(:email)).to contain_exactly("owner@example.test", "clerk@example.test") }
    kept = dir.glob("install.sqlite3.before-import-*").sole
    expect(on_database(kept) { User.pluck(:email) }).to eq(["here@example.test"])
    expect(out.string).to include("the previous database is at #{kept}")
  end

  it "imports an unpacked backup, a directory" do
    unpacked = dir.join("unpacked")
    GoImport::Archive.new(backup, into: unpacked).unpack

    import(unpacked, secret_keys: [secret_key]) { expect(Page.pluck(:path)).to contain_exactly("home", "about") }
  end

  it "says what can't be imported" do
    expect { import(dir.join("nowhere")) }.to raise_error(described_class::Error, /No such file/)
    expect { import(repacked("../escape" => "x")) }.to raise_error(described_class::Error, /climbs out of the archive/)
    expect(dir.glob("**/escape")).to be_empty
  end
end
