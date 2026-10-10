# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("config/secret_key_base")

RSpec.describe SecretKeyBase do
  let(:data_dir) { Dir.mktmpdir("cms-data") }

  after { FileUtils.rm_rf(data_dir) }

  def boot(env) = env.tap { described_class.ensure!(it) }

  it "makes a production install's key on its first boot and finds the same one on every boot after" do
    first = boot({"RAILS_ENV" => "production", "CMS_DATA_DIR" => data_dir})["SECRET_KEY_BASE"]
    again = boot({"RAILS_ENV" => "production", "CMS_DATA_DIR" => data_dir})["SECRET_KEY_BASE"]

    expect(first).to match(/\A\h{128}\z/)
    expect(again).to eq(first)
    expect(File.stat(File.join(data_dir, ".secret_key_base")).mode & 0o777).to eq(0o600)
  end

  it "leaves one that's set, a build's dummy and any other environment alone" do
    expect(boot({"RAILS_ENV" => "production", "CMS_DATA_DIR" => data_dir, "SECRET_KEY_BASE" => "set"})["SECRET_KEY_BASE"]).to eq("set")
    expect(boot({"RAILS_ENV" => "production", "CMS_DATA_DIR" => data_dir, "SECRET_KEY_BASE_DUMMY" => "1"})).not_to have_key("SECRET_KEY_BASE")
    expect(boot({"RAILS_ENV" => "development", "CMS_DATA_DIR" => data_dir})).not_to have_key("SECRET_KEY_BASE")
    expect(Dir.children(data_dir)).to be_empty
  end

  it "agrees on one key when two processes boot at once" do
    keys = Array.new(4) { Thread.new { boot({"RAILS_ENV" => "production", "CMS_DATA_DIR" => data_dir})["SECRET_KEY_BASE"] } }.map(&:value)

    expect(keys.uniq.size).to eq(1)
  end
end
