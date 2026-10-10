# frozen_string_literal: true

# How this install gets content changes in front of visitors. How the site
# renders decides it (Frontend, from what its build reported): a site built
# ahead of time is rebuilt through a provider; a site rendered on demand is
# sent a signed cache purge (Deploys::Purge) instead; a hybrid one gets both.
# A provider knows whether it's configured and how to fire one build; this
# module owns the debounce, what changed in the window, and the rolling log.
#
#   Deploys.current             # the provider Settings › Deploy picked
#   Deploys.ready?              # anything to fire: a provider, or a purge URL
#   Deploys.schedule_later(reason: "page.published", subject: page)  # debounced
#   Deploys.trigger_later                               # now, from "Deploy now"
#
# Content changes arrive in bursts, so schedule_later adds the change
# (Deploys::Change) to the setting's `pending_changes`, stamps `scheduled_at`
# and enqueues Deploys::TriggerJob after DEBOUNCE_WINDOW; the job's
# trigger_now skips if a newer enqueue has overwritten the stamp, so one build
# or purge fires per burst, carrying every change in it.
#
# Three providers ship with the core: a build hook (POST to a URL — Vercel,
# Netlify, any CI), Cloudflare (a Pages or Workers Builds deploy hook) and
# GitHub (a repository_dispatch on the site's repo, Settings › GitHub). A
# plugin adds more with `Cms::Plugins.deploy_provider`.
#
# Which one: the `provider` stored in the deploy setting, else the build hook
# when a hook URL is set — every install that deployed before providers
# existed — else GitHub.
module Deploys
  SETTING_KEY     = "deploy"
  DEBOUNCE_WINDOW = 60.seconds
  STATUSES        = %w[scheduled success failure disabled skipped].freeze
  MAX_LOG_SIZE    = 20
  # Changes kept for one window; past this the build or purge is a full one.
  MAX_PENDING     = 200

  Attempt = Struct.new(:status, :http_status, :error, keyword_init: true)

  CORE_PROVIDERS = {
    "build_hook" => "Deploys::BuildHook",
    "cloudflare" => "Deploys::Cloudflare",
    "github"     => "Deploys::Github"
  }.freeze

  module_function

  # {"build_hook" => Deploys::BuildHook, …}, the core's and enabled plugins'.
  def providers
    CORE_PROVIDERS.transform_values(&:constantize).merge(Cms::Plugins.enabled_deploy_providers)
  end

  def current(config = Setting.get(SETTING_KEY))
    providers.fetch(config["provider"].to_s) { default_for(config) }.new(config)
  end

  def default_for(config)
    config["url"].to_s.start_with?("http") ? Deploys::BuildHook : Deploys::Github
  end

  def config = Setting.get(SETTING_KEY)

  # Settings › Deploy's form and PATCH /api/deploy: a provider only if one by
  # that name exists, `paused` as a boolean. Returns what was saved.
  def configure(attributes)
    incoming = attributes.to_h.stringify_keys
    incoming["paused"] = ActiveModel::Type::Boolean.new.cast(incoming["paused"]) if incoming.key?("paused")
    incoming.delete("provider") unless providers.key?(incoming["provider"].to_s)
    Setting.set(SETTING_KEY, incoming)
    Event.record("settings.deploy_updated", url_set: incoming["url"].to_s.length.positive?, paused: incoming["paused"] == true, provider: incoming["provider"])
    incoming
  end

  def paused?(settings = config) = settings["paused"] == true

  # Whether there's anything to fire: a configured provider, or a site that
  # takes purges.
  def ready?(settings = config) = current(settings).configured? || Frontend.purges?

  # After a content change, batched with whatever else lands in the window.
  def schedule_later(reason:, subject: nil)
    settings = config
    return unless ready?(settings)
    return if paused?(settings)

    change = Deploys::Change.from(reason, subject)
    Setting.set(SETTING_KEY) { |data| {"pending_changes" => (Array(data["pending_changes"]) + [change]).last(MAX_PENDING)} }
    scheduled_at = stamp_schedule(reason)
    Deploys::TriggerJob.set(wait: DEBOUNCE_WINDOW).perform_later(scheduled_at, reason)
  end

  # "Deploy now": no debounce, since a manual trigger means now. The job and
  # the stamp share one timestamp, or trigger_now would see a newer schedule
  # and skip.
  def trigger_later(reason: "manual")
    scheduled_at = stamp_schedule(reason)
    Deploys::TriggerJob.set(wait: 0.seconds).perform_later(scheduled_at, reason)
  end

  # Fires the build or the purge (or both, for a hybrid site) unless a newer
  # schedule superseded this one, with the window's changes, and logs each
  # attempt. "Deploy now" (reason "manual") rebuilds, and purges everything.
  #
  # The schedule is claimed first, in one write, so a job run twice fires
  # once. The changes it fires with leave `pending_changes` only once every
  # attempt succeeded: after a failure they stay, and the next deploy carries
  # them. Changes made while it fires are left for the next one either way.
  def trigger_now(scheduled_at, reason)
    claimed = nil
    Setting.set(SETTING_KEY) do |data|
      claimed = data["scheduled_at"] == scheduled_at ? data : nil
      claimed ? {"scheduled_at" => nil} : {}
    end
    return unless claimed

    settings = claimed
    taken = Array(settings["pending_changes"])
    changes = Deploys::Change.merge(taken)
    provider = current(settings)
    manual = reason == "manual"
    actions = []
    actions << :purge if Frontend.purges?
    actions << :build if provider.configured? && (manual || Frontend.prerendered? || !Frontend.purges?)

    if actions.empty? || paused?(settings)
      record_attempt(status: "disabled", reason: reason, http_status: nil, error: nil, changes: changes.size)
      settle(taken)
    else
      attempts = actions.map do |action|
        started = monotonic_ms
        attempt = if action == :purge
          Deploys::Purge.fire(reason: reason, changes: changes, all: manual)
        else
          fire(provider, reason, changes)
        end
        record_attempt(status: attempt.status, reason: reason, http_status: attempt.http_status, error: attempt.error,
          duration_ms: monotonic_ms - started, via: action == :purge ? "purge" : provider.key, changes: changes.size)
        attempt
      end
      settle(taken) if attempts.all? { it.status == "success" }
    end
  end

  # Takes the changes a deploy went out with off `pending_changes`, leaving
  # any that arrived since.
  def settle(taken)
    return if taken.empty?

    Setting.set(SETTING_KEY) { |data| {"pending_changes" => Array(data["pending_changes"]) - taken} }
  end

  # A plugin's provider may predate `changes:`; it's told only what it takes.
  def fire(provider, reason, changes)
    if provider.method(:fire).parameters.any? { |_, name| name == :changes }
      provider.fire(reason: reason, changes: changes)
    else
      provider.fire(reason: reason)
    end
  end

  def stamp_schedule(reason)
    Time.current.iso8601(6).tap { |at| Setting.set(SETTING_KEY, {"scheduled_at" => at, "last_reason" => reason}) }
  end

  def record_attempt(status:, reason:, http_status:, error:, duration_ms: nil, via: nil, changes: nil)
    entry = {
      "at"          => Time.current.iso8601,
      "status"      => status,
      "reason"      => reason,
      "via"         => via,
      "changes"     => changes,
      "http_status" => http_status,
      "error"       => error,
      "duration_ms" => duration_ms
    }.compact

    # `scheduled_at` is left alone: trigger_now cleared it when it claimed
    # the schedule, and anything there now is a newer one, still to fire.
    Setting.set(SETTING_KEY) do |data|
      {
        "log"           => [entry, *Array(data["log"])].first(MAX_LOG_SIZE),
        "last_status"   => status,
        "last_fired_at" => Time.current.iso8601
      }
    end
  end

  def monotonic_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i
end
