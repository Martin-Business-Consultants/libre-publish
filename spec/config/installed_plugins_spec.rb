# frozen_string_literal: true

require "rails_helper"

# Which copy of each plugin boots, out of the data directory's, the image's
# and the reference plugin, laid out in directories of their own.
RSpec.describe InstalledPlugins do
  let(:root) { Pathname(Dir.mktmpdir("plugins")) }
  let(:data_dir) { root.join("data") }

  after { root.rmtree }

  def plugin(dir, name, version, literal: true)
    path = root.join(dir, name).tap(&:mkpath)
    if literal
      path.join("#{name}.gemspec").write(%(Gem::Specification.new { |spec| spec.version = "#{version}" }))
    else
      path.join("#{name}.gemspec").write(%(Gem::Specification.new { |spec| spec.version = Thing::VERSION }))
      path.join("lib/#{name}").tap(&:mkpath).join("version.rb").write(%(module Thing; VERSION = "#{version}"; end))
    end
    path
  end

  def chosen(env = {})
    stub_const("InstalledPlugins::ROOT", root)
    described_class.chosen({"CMS_DATA_DIR" => data_dir.to_s, "RAILS_ENV" => "production"}.merge(env))
  end

  around { |example| with_env("CMS_DATA_DIR" => data_dir.to_s) { example.run } }

  it "runs the newest copy, and on a tie the data directory's" do
    plugin("plugins", "forms", "1.1.0")
    newer = plugin("data/plugins", "forms", "1.2.0")
    plugin("themes", "healing", "0.3.0")
    plugin("data/plugins", "healing", "0.2.0")
    plugin("plugins", "media", "1.1.0")
    tie = plugin("data/plugins", "media", "1.1.0")

    expect(chosen.transform_values { it.slice(:version, :source) }).to eq(
      "forms" => {version: "1.2.0", source: :installed},
      "healing" => {version: "0.3.0", source: :image},
      "media" => {version: "1.1.0", source: :installed})
    expect(chosen["forms"][:path]).to eq(newer)
    expect(chosen["media"][:path]).to eq(tie)
  end

  it "reads a version a gemspec takes from the plugin's version.rb" do
    plugin("plugins", "thing", "2.0.0", literal: false)

    expect(chosen["thing"][:version]).to eq("2.0.0")
  end

  it "leaves an installed plugin unloaded when it never registers with the CMS, so the install still boots" do
    market = plugin("data/plugins", "market", "0.2.0")
    market.join("lib/market").tap(&:mkpath).join("engine.rb").write("Runwell::Plugins.register :market")
    forms = plugin("data/plugins", "forms", "1.7.2")
    forms.join("lib/forms").tap(&:mkpath).join("engine.rb").write("Cms::Plugins.register :forms")
    allow(described_class).to receive(:chosen).and_return("market" => {path: market, version: "0.2.0", source: :installed})

    described_class.load!

    expect(described_class.failed["market"]).to eq("it isn't a CMS plugin: it's a Runwell plugin, so it's left unloaded. Remove it.")
    expect(described_class.loaded).not_to have_key("market")
    expect(described_class.foreign?(forms)).to be(false)
    expect(described_class.foreign?(plugin("data/plugins", "other", "1.0.0"))).to eq("it never registers with the CMS")
  ensure
    described_class.failed.delete("market")
  end

  it "leaves the data directory's out with CMS_INSTALLED_PLUGINS=off, and the reference plugin out of production" do
    plugin("plugins", "forms", "1.1.0")
    plugin("data/plugins", "forms", "1.2.0")
    plugin("engines", "hello", "0.1.0")

    expect(chosen("CMS_INSTALLED_PLUGINS" => "off")["forms"][:source]).to eq(:image)
    expect(chosen).not_to have_key("hello")
    expect(chosen("RAILS_ENV" => "development")).to have_key("hello")
  end
end
