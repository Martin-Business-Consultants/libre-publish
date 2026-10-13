# frozen_string_literal: true

# POST /csp-reports?surface=website|admin: where browsers send what a
# Content-Security-Policy blocked (report-uri). Open to anyone, as a report
# comes from any visitor's browser: small bodies only, and only an origin, a
# directive and a path are kept (CspReport), never the visitor.
class CspReportsController < ActionController::Base
  MAX_BYTES = 16_384

  skip_forgery_protection

  def create
    return head(:payload_too_large) if request.content_length.to_i > MAX_BYTES

    body = request.raw_post.to_s.first(MAX_BYTES)
    payloads = Array.wrap(JSON.parse(body))
    payloads.first(20).each { CspReport.record(it.to_h, surface: params[:surface].to_s) if it.is_a?(Hash) }
    head :no_content
  rescue JSON::ParserError
    head :bad_request
  end
end
