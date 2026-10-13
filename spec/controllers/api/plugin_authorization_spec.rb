# frozen_string_literal: true

require "rails_helper"

# A plugin's API controllers are defined outside app/ (this file stands in
# for one). Straight on Api::BaseController they keep the old default, open
# until they say otherwise; under a base of the plugin's that enforces, they
# enforce too.
RSpec.describe Api::BaseController do
  it "leaves a plugin's controller made straight on it open until it enforces" do
    expect(Class.new(described_class)._skip_authorization).to be(true)
  end

  it "keeps a plugin's base's enforcement for every controller under it" do
    base = Class.new(described_class) { enforce_authorization }
    child = Class.new(base) { requires_capability "pages:read", only: :index }
    expect(child._skip_authorization).to be(false)
    expect(Class.new(child)._skip_authorization).to be(false)
  end
end
