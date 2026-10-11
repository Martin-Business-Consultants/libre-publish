# frozen_string_literal: true

# A nonce for each response's inline scripts (javascript_tag nonce: true, the
# importmap), which the admin's Content-Security-Policy allows and nothing
# else inline. The policy itself is the admin's (ApplicationController's
# `content_security_policy`), not every response's: the public website runs
# what its owners paste into the Scripts global (analytics, a chat widget),
# which carries no nonce.
Rails.application.configure do
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
end
