# frozen_string_literal: true

require "rails_helper"

# A site moved from another install without that install's keys (or an
# install whose keys changed) holds values this one can't decrypt. They
# still work where they're only compared by digest; the pages that show
# them say so rather than failing.
RSpec.describe "Values encrypted with another install's key", type: :request do
  let(:admin) { create(:user) }

  def foreign(text)
    ActiveRecord::Encryption::Encryptor.new.encrypt(text, key_provider: ActiveRecord::Encryption::DerivedSecretKeyProvider.new("another install's key"))
  end

  # Written raw: update_columns would encrypt it again with this install's key.
  def write_raw(model, column, value, id)
    ActiveRecord::Base.connection.execute(model.sanitize_sql(["UPDATE #{model.table_name} SET #{column} = ? WHERE id = ?", value, id]))
  end

  before { sign_in_as admin }

  it "shows the API token page, and says a token it can't read must be rotated to be shown" do
    token = ApiToken.for(admin)
    write_raw(ApiToken, :token, foreign("lp_old"), token.id)

    get settings_api_token_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("rotate it to get one you can copy")

    post settings_api_token_reveal_path, as: :json
    expect(response).to have_http_status(:gone)
  end

  it "rotates a token it can't read, so it can be shown again" do
    token = ApiToken.for(admin)
    write_raw(ApiToken, :token, foreign("lp_old"), token.id)

    post settings_api_token_rotation_path

    expect(token.reload.visible?).to be(true)
    expect(ServiceToken.issue!(name: "PRODUCTION", role: Role.system_admin).tap { write_raw(ServiceToken, :token, foreign("lps_old"), it.id) }
      .reload.rotate!).to start_with(ServiceToken::PREFIX)
  end

  # cms login (the agent installer): the CLI waits, someone approves, and the
  # next poll hands over the person's token, rotating one that can't be read.
  it "lets the CLI log in as someone whose token it can't read" do
    write_raw(ApiToken, :token, foreign("lp_old"), ApiToken.for(admin).id)
    post "/api/device/code", params: {hostname: "laptop"}
    device_code = JSON.parse(response.body)["device_code"]

    post "/api/device/token", params: {device_code: device_code}
    expect(response).to have_http_status(:accepted)

    DeviceAuthorization.find_by(device_code: device_code).approve!(admin)
    post "/api/device/token", params: {device_code: device_code}

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).to_s).to include(ApiToken::PREFIX)
  end

  it "takes a new secret over one it can't read" do
    record = Setting.find_or_create_by!(key: "github")
    write_raw(Setting, :secrets, foreign({token: "ghp_old"}.to_json), record.id)

    Setting.set_secret("github", token: "ghp_new")

    expect(Setting.secret("github", "token")).to eq("ghp_new")
  end

  # The keys might only be misconfigured: what's cleared stays recoverable.
  it "keeps what it clears in the audit log, where the right keys can still read it" do
    record = Setting.find_or_create_by!(key: "github")
    ciphertext = foreign({token: "ghp_old"}.to_json)
    write_raw(Setting, :secrets, ciphertext, record.id)

    Setting.set_secret("github", token: "ghp_new")

    row = AuditLog.find_by!(action: "setting.unreadable_value_cleared")
    expect(row.target).to eq(record)
    expect(row.metadata).to include("attribute" => "secrets", "ciphertext" => ciphertext)
  end

  it "shows the service tokens page with one it can't read" do
    service = ServiceToken.issue!(name: "PRODUCTION", role: Role.system_admin)
    write_raw(ServiceToken, :token, foreign("lps_old"), service.id)

    get settings_service_tokens_path

    expect(response).to have_http_status(:ok)
    expect(service.reload.visible?).to be(false)
  end

  it "reads a setting's secrets it can't decrypt as not set" do
    record = Setting.find_or_create_by!(key: "github")
    write_raw(Setting, :secrets, foreign({token: "ghp_old"}.to_json), record.id)

    expect(record.reload.secrets_hash).to eq({})

    get settings_github_path
    expect(response).to have_http_status(:ok)
  end
end
