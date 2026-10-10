# frozen_string_literal: true

# Specs don't touch DNS: every host resolves to a public documentation
# address (TEST-NET-3), unless a spec sets OutboundUrl.resolver itself.
RSpec.configure do |config|
  config.around do |example|
    previous = OutboundUrl.instance_variable_get(:@resolver)
    OutboundUrl.resolver = ->(_host) { ["203.0.113.10"] }
    example.run
  ensure
    OutboundUrl.resolver = previous
  end
end
