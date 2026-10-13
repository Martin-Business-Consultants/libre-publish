# frozen_string_literal: true

# A source a Content-Security-Policy blocked, as browsers report it
# (CspReportsController): the website's or the admin's, which directive, the
# origin it came from, the page it was on, how often and when last. Inline
# code and the browser's own extensions are left out: there's nothing to
# allow for them by address.
class CspReport < ApplicationRecord
  SURFACES = %w[website admin].freeze
  KEEP_FOR = 30.days
  MAX = 500

  validates :surface, inclusion: {in: SURFACES}

  scope :open, -> { where(dismissed: false).where(last_seen_at: KEEP_FOR.ago..).order(last_seen_at: :desc) }

  # Records one report body (the classic `csp-report` shape, or a Reporting API entry).
  def self.record(payload, surface:)
    return unless SURFACES.include?(surface)

    body = payload["csp-report"] || payload["body"] || payload
    directive = (body["effective-directive"] || body["effectiveDirective"] || body["violated-directive"] || body["violatedDirective"]).to_s.split.first
    blocked = origin(body["blocked-uri"] || body["blockedURL"])
    return unless directive.in?(SecurityPolicy::DIRECTIVES + %w[script-src-elem style-src-elem]) && blocked

    directive = directive.delete_suffix("-elem")
    page = URI.parse((body["document-uri"] || body["documentURL"]).to_s).path.to_s.first(200) rescue nil # rubocop:disable Style/RescueModifier
    report = find_or_initialize_by(surface: surface, directive: directive, blocked: blocked)
    report.new_record? ? report.assign_attributes(count: 1) : report.count += 1
    report.update!(page: page.presence || report.page, last_seen_at: Time.current)
    where(last_seen_at: ...KEEP_FOR.ago).delete_all if rand < 0.01
    report
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  def self.origin(uri)
    uri = uri.to_s
    return if uri.blank? || uri.in?(%w[inline eval self data blob wasm-eval]) || uri.start_with?("chrome-extension", "moz-extension", "safari-extension")

    parsed = URI.parse(uri)
    "#{parsed.scheme}://#{parsed.host}" if parsed.host && parsed.scheme.in?(%w[http https wss ws])
  rescue URI::InvalidURIError
    nil
  end
end
