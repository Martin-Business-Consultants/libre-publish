# frozen_string_literal: true

# The exceptions app (config.exceptions_app): what answers when a request
# fails before a controller can — an /api path no route matches, or an error
# raised outside an action. An /api request gets JSON in the API's one error
# shape (Api::ErrorResponses), {"error": "not_found", "message": "Not Found"};
# everything else gets Rails' public pages, as before.
class ApiExceptions
  def call(env)
    return public_exceptions.call(env) unless api?(env)

    status = env["PATH_INFO"].delete_prefix("/").to_i
    status = 500 unless Rack::Utils::HTTP_STATUS_CODES.key?(status)
    message = Rack::Utils::HTTP_STATUS_CODES.fetch(status)
    code = (status == 500) ? "internal_error" : Rack::Utils::SYMBOL_TO_STATUS_CODE.key(status).to_s
    body = JSON.generate(error: code, message: message)
    [status, {"content-type" => "application/json; charset=utf-8", "content-length" => body.bytesize.to_s}, [body]]
  end

  private

  def public_exceptions
    @public_exceptions ||= ActionDispatch::PublicExceptions.new(Rails.public_path)
  end

  def api?(env)
    path = env["action_dispatch.original_path"] || env["ORIGINAL_FULLPATH"].to_s
    path == "/api" || path.start_with?("/api/")
  end
end
