# frozen_string_literal: true

# A production install checks its configuration as it boots (Cms::EnvCheck):
# a missing secret or a misread value stops it, naming each problem; the
# rest is logged. The Docker build's asset precompile runs without the
# install's environment (SECRET_KEY_BASE_DUMMY), so it isn't checked.
Rails.application.config.after_initialize do
  if Rails.env.production? && ENV["SECRET_KEY_BASE_DUMMY"].blank?
    Cms::EnvCheck.new(ENV, secret_key_base: Rails.application.credentials.secret_key_base).call!.each do |warning|
      Rails.logger.warn("[config] #{warning}")
    end
  end
end
