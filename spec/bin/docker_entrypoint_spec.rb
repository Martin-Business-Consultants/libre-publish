# frozen_string_literal: true

require "rails_helper"
require "open3"

# bin/docker-entrypoint, run for real against a stand-in image and data
# volume: each app's bin/rails is a stub that says where it ran and whether
# it can prepare its database.
RSpec.describe "bin/docker-entrypoint" do
  let(:root) { Pathname(Dir.mktmpdir("entrypoint")) }
  let(:image) { root.join("image") }
  let(:data) { root.join("data") }
  let(:release) { data.join("releases/v9.0.0") }

  after { root.rmtree }

  def app(dir, version:, prepares:)
    dir.join("bin").mkpath
    dir.join("VERSION").write("#{version}\n")
    dir.join("bin/rails").write(<<~SH)
      #!/bin/bash
      case "$1" in
        server) echo "serving #{version}";;
        db:prepare) #{prepares ? "echo prepared #{version}" : "echo 'NoMethodError: it broke' >&2; exit 1"};;
        *) exit 0;;
      esac
    SH
    dir.join("bin/rails").chmod(0o755)
  end

  # As the container runs it: in the image's directory, without this
  # process's bundle.
  def boot
    Bundler.with_unbundled_env do
      Open3.capture2e({"CMS_IMAGE_ROOT" => image.to_s, "CMS_DATA_DIR" => data.to_s, "BUNDLE_PATH" => "/image/bundle"},
        Rails.root.join("bin/docker-entrypoint").to_s, "./bin/rails", "server", chdir: image.to_s)
    end
  end

  before { app(image, version: "1.0.0", prepares: true) }

  it "runs the newer release the install updated itself to" do
    app(release, version: "9.0.0", prepares: true)
    data.join("releases/current").make_symlink("v9.0.0")

    output, status = boot

    expect(status).to be_success
    expect(output).to include("Running CMS 9.0.0", "prepared 9.0.0", "serving 9.0.0")
  end

  it "goes back to the image when that release won't start, and says why" do
    app(release, version: "9.0.0", prepares: false)
    data.join("releases/current").make_symlink("v9.0.0")

    output, status = boot

    expect(status).to be_success
    expect(output).to include("didn't start; going back to the image's 1.0.0", "prepared 1.0.0", "serving 1.0.0")
    expect(data.join("releases/current")).not_to exist
    expect(data.join("releases/v9.0.0.failed").read).to include("NoMethodError: it broke")
  end

  it "runs the image when there's no release, and stops when it won't prepare" do
    output, status = boot
    expect(output).to include("prepared 1.0.0", "serving 1.0.0")
    expect(status).to be_success

    app(image, version: "1.0.0", prepares: false)
    _, status = boot
    expect(status).not_to be_success
  end
end
