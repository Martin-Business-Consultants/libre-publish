# frozen_string_literal: true

# Read-only viewer over the audit log. Filters keep the page useful even
# when the table grows: an editor can ask "what did Bob do this week?" or
# "who deleted this page?" without scrolling.
class AuditLogsController < ApplicationController
  requires_capability "audit_log:read", only: [:index]

  def index
    scope = AuditLog.recent.search_list(search_term)
    scope = scope.where(action: AuditLog.names_for(params[:action_filter])) if params[:action_filter].present?
    scope = scope.where("actor_label LIKE ?", "%#{AuditLog.sanitize_sql_like(params[:actor])}%") if params[:actor].present?
    scope = scope.where("created_at >= ?", parse_time(params[:from])) if parse_time(params[:from])
    scope = scope.where("created_at <= ?", through(params[:to]))      if parse_time(params[:to])

    @entries       = paginate(scope)
    @known_actions = AuditLog.known_actions
  end

  private

  # A day alone (the date pickers') runs to its end, so "to" includes it.
  def through(value)
    time = parse_time(value)
    value.to_s.match?(/\A\d{4}-\d{2}-\d{2}\z/) ? time.end_of_day : time
  end

  def parse_time(value)
    Time.zone.parse(value.to_s) if value.present?
  rescue ArgumentError, TypeError
    nil
  end
end
