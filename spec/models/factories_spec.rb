# frozen_string_literal: true

require "rails_helper"

# Every factory builds a record that saves as it stands.
RSpec.describe "Factories" do
  FactoryBot.factories.map(&:name).each do |name|
    it "builds a valid #{name}" do
      expect(create(name)).to be_persisted
    end
  end
end
