# frozen_string_literal: true

require "net/http"
require "openssl"

# The plugin directory: the plugins and themes Libre Publish vouches for,
# each pinned to the commit of its release that was reviewed
# (github.com/Martin-Business-Consultants/libre-publish-plugins). The list is
# signed with the directory's Ed25519 key and checked against the public key
# here, so a list that was tampered with on the way, or by whoever can push
# to it without the key, is refused. Installing from it downloads that exact
# commit (PluginChange, pinned), so a release retagged afterwards can't swap
# in other code.
#
# Fetched daily with the update check and kept in the "plugin_directory"
# setting, so a page never waits on GitHub.
#
#   PluginDirectory.refresh            # fetch, verify and store; quiet on failure
#   PluginDirectory.plugins            # [Entry, …] (kind "plugin")
#   PluginDirectory.themes
#   PluginDirectory.find_by_repo("owner/name")
#
# A self-hosted directory: CMS_PLUGIN_DIRECTORY_URL (the JSON; the signature
# is beside it, + ".sig") and CMS_PLUGIN_DIRECTORY_KEY (its public key, PEM).
module PluginDirectory
  class Invalid < StandardError; end

  SETTING_KEY = "plugin_directory"
  DEFAULT_URL = "https://raw.githubusercontent.com/Martin-Business-Consultants/libre-publish-plugins/main/directory.json"
  PUBLIC_KEY = <<~PEM
    -----BEGIN PUBLIC KEY-----
    MCowBQYDK2VwAyEAgeMubot8BzLp7OK76VQRjL2nxd5mW/6VjgUcU1Eu3Cc=
    -----END PUBLIC KEY-----
  PEM

  Entry = Data.define(:key, :kind, :name, :description, :repo, :author, :homepage, :version, :commit, :requires) do
    def theme? = kind == "theme"

    def compatible?
      requires.blank? || Gem::Requirement.new(requires).satisfied_by?(Cms.version)
    rescue ArgumentError
      false
    end

    def installed? = InstalledPlugins.loaded.key?(key) || InstalledPlugins.present.key?(key)
  end

  module_function

  def url = ENV["CMS_PLUGIN_DIRECTORY_URL"].presence || DEFAULT_URL
  def public_key = OpenSSL::PKey.read(ENV["CMS_PLUGIN_DIRECTORY_KEY"].presence || PUBLIC_KEY)

  def refresh
    refresh!
  rescue StandardError => error
    Rails.logger.warn("[plugin_directory] #{error.class}: #{error.message}")
    nil
  end

  def refresh!
    body = get(url)
    signature = get("#{url}.sig")
    data = verified(body, signature)
    Setting.set(SETTING_KEY, {"entries" => data.fetch("plugins"), "checked_at" => Time.current.iso8601})
  end

  # The list, parsed, if its signature is the directory key's.
  def verified(body, signature)
    raise Invalid, "The plugin directory's signature doesn't match its key." unless public_key.verify(nil, signature.unpack1("m"), body)

    JSON.parse(body).tap { raise Invalid, "The plugin directory has no plugins list." unless it["plugins"].is_a?(Array) }
  rescue ArgumentError, OpenSSL::PKey::PKeyError, JSON::ParserError => error
    raise Invalid, "The plugin directory couldn't be read: #{error.message}"
  end

  def entries
    Array(Setting.get(SETTING_KEY)["entries"]).filter_map do |row|
      Entry.new(**Entry.members.to_h { [it, row[it.to_s]] }.merge(kind: row["kind"].presence || "plugin"))
    rescue ArgumentError
      nil
    end
  end

  def plugins = entries.reject(&:theme?)
  def themes = entries.select(&:theme?)
  def find_by_repo(repo) = entries.find { it.repo.to_s.casecmp?(repo.to_s) }
  def find(key) = entries.find { it.key == key.to_s }
  def checked_at = Setting.get(SETTING_KEY)["checked_at"].presence&.then { Time.zone.parse(it) }

  def get(address)
    uri = URI(address)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 15) do |http|
      http.request(Net::HTTP::Get.new(uri))
    end
    raise Invalid, "#{address} answered #{response.code}." unless response.is_a?(Net::HTTPSuccess)

    response.body
  end
end
