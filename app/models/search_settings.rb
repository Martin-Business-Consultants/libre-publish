# frozen_string_literal: true

# Settings › Search: how the website meets search engines and AI. Kept in the
# "search" setting.
#
#   ai_search     allow | block   AI answer engines that cite and link to the
#                                 site (ChatGPT search, Perplexity, Claude…)
#   ai_training   allow | block   crawlers that gather text to train models
#                                 (GPTBot, ClaudeBot, Google-Extended, CCBot…)
#   organization  Organization | LocalBusiness | Person: who the site is, in
#                 its structured data
#   same_as       the organization's profiles elsewhere (one URL a line), so
#                 search engines and AI tie them to it
#   robots_extra  lines added to robots.txt as written
module SearchSettings
  SETTING_KEY = "search"
  CHOICES = %w[allow block].freeze
  ORGANIZATION_TYPES = %w[Organization LocalBusiness Person].freeze

  # Who's who among the crawlers, by what they do. A search engine's own
  # crawler (Googlebot, Bingbot) is never named: blocking it takes the site
  # out of search. Google-Extended and Applebot-Extended only say whether
  # Gemini and Apple Intelligence may train on the site; Google Search and
  # Siri still crawl it.
  AI_SEARCH_BOTS = %w[OAI-SearchBot ChatGPT-User PerplexityBot Perplexity-User Claude-SearchBot Claude-User
    DuckAssistBot MistralAI-User].freeze
  AI_TRAINING_BOTS = %w[GPTBot ClaudeBot anthropic-ai Google-Extended Applebot-Extended CCBot meta-externalagent
    Bytespider Amazonbot cohere-ai Diffbot].freeze

  DEFAULTS = {"ai_search" => "allow", "ai_training" => "allow", "organization" => "Organization", "same_as" => [], "robots_extra" => ""}.freeze

  module_function

  def get
    data = DEFAULTS.merge(Setting.get(SETTING_KEY).slice(*DEFAULTS.keys))
    data.merge("same_as" => Array(data["same_as"]))
  end

  def update(submitted)
    submitted = submitted.to_h.stringify_keys
    Setting.set(SETTING_KEY, {
      "ai_search" => submitted["ai_search"].presence_in(CHOICES) || "allow",
      "ai_training" => submitted["ai_training"].presence_in(CHOICES) || "allow",
      "organization" => submitted["organization"].presence_in(ORGANIZATION_TYPES) || "Organization",
      "same_as" => submitted["same_as"].to_s.split(/\s+/).select { it.match?(%r{\Ahttps?://\S+\z}) }.uniq,
      "robots_extra" => submitted["robots_extra"].to_s.strip
    })
  end

  def ai_search? = get["ai_search"] == "allow"
  def ai_training? = get["ai_training"] == "allow"
end
