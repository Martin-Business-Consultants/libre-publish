# frozen_string_literal: true

# Every /api error is JSON, in one shape: {"error": "<code>", "message": …},
# plus `errors` (per field, on 422) or `capability` (on 403) where a client
# acts on them. What the API already answered — not_found, invalid,
# forbidden — keeps its body byte for byte; this adds the cases that used to
# fall through to Rails' exception page:
#
#   400 bad_request      a missing parameter, a body that isn't JSON
#   406 not_acceptable   a format the endpoint doesn't serve
#   409 conflict         someone saved the record since it was read
#   429 rate_limited     too many requests (Api::V1::BaseController)
#   500 internal_error   anything else: logged and reported, never a backtrace
#
# Development and test re-raise the 500 (consider_all_requests_local), so a
# bug shows its page or fails its spec instead of turning into JSON.
module Api::ErrorResponses
  extend ActiveSupport::Concern

  included do
    # Handlers declared later win, so the catch-all goes first and
    # Forbidden — declared by Authorization, before this — comes again
    # after it, or the catch-all would answer it.
    rescue_from StandardError, with: :render_internal_error
    rescue_from Authorization::Forbidden, with: :render_forbidden
    rescue_from ActionController::ParameterMissing, ActionController::BadRequest,
      ActionDispatch::Http::Parameters::ParseError, with: :render_bad_request
    rescue_from ActionController::UnknownFormat, with: :render_not_acceptable
    rescue_from ActiveRecord::StaleObjectError, with: :render_conflict
  end

  private

  def render_bad_request(error)
    render json: {error: "bad_request", message: error.message}, status: :bad_request
  end

  def render_not_acceptable(_error)
    render json: {error: "not_acceptable", message: "This endpoint doesn't serve that format."}, status: :not_acceptable
  end

  def render_conflict(_error)
    render json: {error: "conflict", message: "It changed since you read it. Read it again and retry."}, status: :conflict
  end

  def render_rate_limited
    response.set_header("Retry-After", "60")
    render json: {error: "rate_limited", message: "Too many requests. Wait a minute and retry."}, status: :too_many_requests
  end

  def render_internal_error(error)
    raise error if Rails.application.config.consider_all_requests_local

    Rails.error.report(error, handled: true, context: {path: request.path})
    render json: {error: "internal_error", message: "Something went wrong on the CMS."}, status: :internal_server_error
  end
end
