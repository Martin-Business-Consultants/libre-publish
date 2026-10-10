# frozen_string_literal: true

require "rails_helper"

# Every API action this app (and its bundled engines) answers says who may
# call it: a capability (`requires_capability`), or open to any caller on
# purpose (`skip_authorization only:`). Api::BaseController refuses what says
# neither, so this is what keeps a new endpoint from being written open — or
# refused for everyone — by accident.
RSpec.describe "Architecture: API authorization" do
  # Controllers that answer without a signed-in caller at all, and why.
  WITHOUT_AUTHORIZATION = {
    "Api::DeviceAuthorizationsController" => "the CLI's device login: how a machine gets its first credential"
  }.freeze

  def own?(klass)
    file = Object.const_source_location(klass.name)&.first.to_s
    file.start_with?(Rails.root.join("app/").to_s, Rails.root.join("engines/").to_s)
  end

  it "has every API action declare a capability, or open itself on purpose" do
    Rails.application.eager_load!
    actions = Rails.application.routes.routes.filter_map do |route|
      next unless route.path.spec.to_s.start_with?("/api/") && route.defaults[:controller] && route.defaults[:action]

      klass = "#{route.defaults[:controller].camelize}Controller".safe_constantize
      [klass, route.defaults[:action]] if klass && own?(klass)
    end.uniq

    undeclared = actions.reject do |klass, action|
      next true if WITHOUT_AUTHORIZATION.key?(klass.name)
      next false unless klass.respond_to?(:authorization_for)

      access = klass.authorization_for(action)
      access && !(access == :skipped && klass._skip_authorization)
    end

    expect(undeclared.map { |klass, action| "#{klass.name}##{action}" }).to be_empty, <<~MESSAGE
      These API actions don't say who may call them. Give each a
      `requires_capability "…", only: :action`, or `skip_authorization only: :action`
      with a comment saying why any caller may.
    MESSAGE
  end
end
