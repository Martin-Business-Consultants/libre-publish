# frozen_string_literal: true

# /robots.txt: everything open to search engines but the admin and the API
# (all of it closed on a headless install, whose site is elsewhere),
# AI crawlers let in or kept out by kind (SearchSettings), and where the
# sitemap is.
class Website::Robots
  def initialize(base_url, settings: SearchSettings.get)
    @base_url = base_url.chomp("/")
    @settings = settings
  end

  def to_s
    # Headless, this host is the admin and the API: the site is elsewhere.
    return "User-agent: *\nDisallow: /\n" unless Website.enabled?

    groups = [["*", ["Allow: /", "Disallow: /#{Cms::PATH}/", "Disallow: /api/"]]]
    groups << [SearchSettings::AI_SEARCH_BOTS, ["Disallow: /"]] if @settings["ai_search"] == "block"
    groups << [SearchSettings::AI_TRAINING_BOTS, ["Disallow: /"]] if @settings["ai_training"] == "block"

    lines = groups.flat_map do |agents, rules|
      Array(agents).map { "User-agent: #{it}" } + rules + [""]
    end
    lines << @settings["robots_extra"] << "" if @settings["robots_extra"].present?
    lines << "Sitemap: #{@base_url}/sitemap.xml"
    lines.join("\n") + "\n"
  end
end
