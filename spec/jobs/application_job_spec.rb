# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationJob do
  include ActiveJob::TestHelper

  let(:busy_job) do
    Class.new(described_class) do
      def self.name = "BusyJob"

      def perform = raise(ActiveRecord::StatementTimeout, "database is locked")
    end
  end

  it "tries again when the database was busy" do
    expect { busy_job.perform_now }.to have_enqueued_job(busy_job)
  end

  it "drops a job whose record is gone" do
    expect(described_class.rescue_handlers.map(&:first)).to include("ActiveJob::DeserializationError")
  end
end
