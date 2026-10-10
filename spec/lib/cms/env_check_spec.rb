# frozen_string_literal: true

require "rails_helper"

RSpec.describe Cms::EnvCheck do
  let(:good) do
    {"SECRET_KEY_BASE" => "a" * 128, "APP_HOST" => "cms.example.com", "SMTP_PASSWORD" => "x"}
  end

  def check(env, **options) = described_class.new(env, **options).call

  it "passes a complete configuration" do
    expect(check(good)).to eq([[], []])
  end

  it "needs a SECRET_KEY_BASE, from the environment or credentials" do
    errors, = check(good.except("SECRET_KEY_BASE"))
    expect(errors.join).to include("SECRET_KEY_BASE is missing")

    expect(check(good.except("SECRET_KEY_BASE"), secret_key_base: "b" * 128).first).to be_empty
  end

  it "warns about a short SECRET_KEY_BASE, and partial AR_ENCRYPTION_* keys" do
    _, warnings = check(good.merge("SECRET_KEY_BASE" => "short", "AR_ENCRYPTION_PRIMARY_KEY" => "k"))
    expect(warnings.join("\n")).to include("5 characters").and include("AR_ENCRYPTION_PRIMARY_KEY of the AR_ENCRYPTION_* keys")
  end

  it "warns without APP_HOST, and refuses one with a scheme or path" do
    expect(check(good.except("APP_HOST")).last.join).to include("APP_HOST isn't set")
    expect(check(good.merge("APP_HOST" => "https://cms.example.com/")).first.join).to include("no scheme or path")
    expect(check(good.merge("APP_HOST" => "localhost:3000")).first).to be_empty
  end

  it "refuses values the app would misread" do
    errors, = check(good.merge(
      "APP_PROTOCOL" => "htps", "CMS_FORCE_SSL" => "yes", "SMTP_PORT" => "25x", "CMS_UPDATES" => "auto",
      "MAIL_FROM_ADDRESS" => "nobody"
    ))
    %w[APP_PROTOCOL CMS_FORCE_SSL SMTP_PORT CMS_UPDATES MAIL_FROM_ADDRESS].each do |name|
      expect(errors).to include(start_with("#{name} is"))
    end
  end

  it "takes an installed plugin's update strategy for CMS_UPDATES" do
    expect(check(good.merge("CMS_UPDATES" => "deployer")).first.join).to include("CMS_UPDATES is")

    register_update_strategy("deployer")
    expect(check(good.merge("CMS_UPDATES" => "deployer")).first.join).not_to include("CMS_UPDATES")
  end

  it "warns that mail can't go out without SMTP_PASSWORD" do
    expect(check(good.except("SMTP_PASSWORD")).last.join).to include("can't send mail")
  end

  it "call! raises naming every error, and returns the warnings" do
    expect { described_class.new(good.merge("APP_PROTOCOL" => "ftp", "PORT" => "x")).call! }
      .to raise_error(described_class::Invalid, /APP_PROTOCOL.*\n.*PORT/m)
    expect(described_class.new(good.except("SMTP_PASSWORD")).call!).to be_one
  end
end
