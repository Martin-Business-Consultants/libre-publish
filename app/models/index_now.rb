# frozen_string_literal: true

require "net/http"

# IndexNow: when a page or entry is published, changed or taken down, the
# CMS tells the search engines that share IndexNow (Bing, which ChatGPT
# search draws on, Yandex, Seznam, Naver…) at once, instead of waiting to be
# crawled. The site proves it's its own with a key served at /<key>.txt.
# Only for a website the CMS draws, on a public address (Settings › General's
# site URL), and only while Settings › Search leaves it on.
module IndexNow
  ENDPOINT = "https://api.indexnow.org/indexnow"
  EVENTS = %w[page.published page.updated page.unpublished page.deleted entry.published entry.updated entry.unpublished entry.deleted].freeze

  module_function

  # The site's key, made the first time it's asked for.
  def key
    SearchSettings.get["indexnow_key"].presence || SecureRandom.hex(16).tap { Setting.set(SearchSettings::SETTING_KEY, {"indexnow_key" => it}) }
  end

  def base_url = Setting.get("general")["site_base_url"].to_s.chomp("/")

  def enabled?
    return false if Rails.configuration.x.indexnow == false # the test suite's, but for IndexNow's own specs
    return false unless Website.enabled? && SearchSettings.get["indexnow"] != false

    host = URI(base_url).host.to_s
    host.include?(".") && !host.match?(/\A(localhost|127\.|0\.0\.0\.0)|\.(test|local|localhost|example)\z/)
  rescue URI::InvalidURIError
    false
  end

  # Every page and entry event comes here; the addresses go out in a job.
  def subscribe!
    ActiveSupport::Notifications.subscribe(/\A(page|entry)\.\w+\.cms\z/) do |event|
      name = event.name.delete_suffix(".cms")
      url = event.payload.dig(:data, :url) || event.payload.dig(:data, "url")
      IndexNowJob.perform_later([url]) if EVENTS.include?(name) && url.present? && IndexNow.enabled?
    end
  end

  def submit(urls)
    urls = Array(urls).compact_blank.uniq.select { it.start_with?(base_url) }
    return if urls.empty? || !enabled?

    uri = URI(ENDPOINT)
    body = {host: URI(base_url).host, key: key, keyLocation: "#{base_url}/#{key}.txt", urlList: urls}.to_json
    Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) do |http|
      http.post(uri.path, body, "Content-Type" => "application/json; charset=utf-8")
    end
  end
end
