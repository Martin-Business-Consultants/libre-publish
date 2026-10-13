# frozen_string_literal: true

# robots.txt: by default made from Settings › Search (everything open to
# search engines but the admin and the API, AI crawlers let in or kept out by
# kind, the extra lines as written, and where the sitemap is), or, when
# someone wrote their own on the Sitemap screen, that as written.
#
# For this host (/robots.txt) a headless install keeps everything out: its
# site is elsewhere. For the site a frontend builds (`frontend: true`,
# GET /api/v1/robots), the admin and API lines are left out: they're on the
# CMS's host, not the site's.
class Website::Robots
  DIRECTIVES = %w[user-agent allow disallow sitemap crawl-delay host clean-param].freeze

  def initialize(base_url, settings: SearchSettings.get, frontend: false)
    @base_url = base_url.to_s.chomp("/")
    @settings = settings
    @frontend = frontend
  end

  def custom? = @settings["robots_mode"] == "custom" && @settings["robots_custom"].present?

  def to_s
    # Headless, this host is the admin and the API: the site is elsewhere.
    return "User-agent: *\nDisallow: /\n" unless @frontend || Website.enabled?
    return @settings["robots_custom"].to_s.strip + "\n" if custom?

    generated
  end

  # What robots.txt would be made from the choices, whatever is in use.
  def generated
    rules = @frontend ? ["Allow: /"] : ["Allow: /", "Disallow: /#{Cms::PATH}/", "Disallow: /api/"]
    groups = [["*", rules]]
    groups << [SearchSettings::AI_SEARCH_BOTS, ["Disallow: /"]] if @settings["ai_search"] == "block"
    groups << [SearchSettings::AI_TRAINING_BOTS, ["Disallow: /"]] if @settings["ai_training"] == "block"

    lines = groups.flat_map do |agents, group|
      Array(agents).map { "User-agent: #{it}" } + group + [""]
    end
    lines << @settings["robots_extra"] << "" if @settings["robots_extra"].present?
    lines << "Sitemap: #{@base_url}/sitemap.xml"
    lines.join("\n") + "\n"
  end

  # What's likely wrong with a robots.txt, said plainly: [warning].
  def self.warnings(text)
    lines = text.to_s.lines.map(&:strip)
    found = []
    agent = nil
    lines.each_with_index do |line, index|
      next if line.empty? || line.start_with?("#")

      field, value = line.split(":", 2).map(&:strip)
      unless value && DIRECTIVES.include?(field.to_s.downcase)
        found << "Line #{index + 1} isn't a rule crawlers know (#{line.truncate(40)}): write “Field: value”, as User-agent, Allow, Disallow or Sitemap."
        next
      end

      case field.downcase
      when "user-agent" then agent = value
      when "disallow"
        found << "“Disallow: /” for every crawler (User-agent: *) keeps the whole site out of search." if agent == "*" && value == "/"
      when "sitemap"
        found << "The Sitemap line must be a full address (https://…), not “#{value}”." unless value.match?(%r{\Ahttps?://})
      end
    end
    found << "It doesn't say where the sitemap is: add “Sitemap: https://…/sitemap.xml”." unless lines.any? { it.downcase.start_with?("sitemap:") }
    found << "No User-agent line: crawlers ignore rules that don't follow one." if lines.any? { it.downcase.start_with?("allow:", "disallow:") } && lines.none? { it.downcase.start_with?("user-agent:") }
    found.uniq
  end
end
