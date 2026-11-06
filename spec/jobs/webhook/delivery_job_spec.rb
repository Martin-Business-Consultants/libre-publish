# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhook::DeliveryJob do
  let(:webhook) { Webhook.create!(name: "test", url: "https://hooks.example.com/in", events: ["page.published"]) }

  it "delivers the event to the webhook, named by the job's id" do
    job = described_class.new(webhook.id, "page.published", {"slug" => "about"})
    expect_any_instance_of(Webhook).to receive(:deliver_now).with("page.published", {"slug" => "about"}, delivery_id: job.job_id)

    job.perform_now
  end

  it "sends a delivery the receiver couldn't take again later, under the same id, and not one it refused" do
    responses = [500, 404]
    ids = []
    allow_any_instance_of(Net::HTTP).to receive(:request) do |_http, request|
      ids << request["X-CMS-Delivery"]
      code = responses.shift
      (code == 500 ? Net::HTTPServerError : Net::HTTPNotFound).new("1.1", code.to_s, "")
    end

    job = described_class.new(webhook.id, "page.published", {"slug" => "about"})
    expect { job.perform_now }.to have_enqueued_job(described_class).with(webhook.id, "page.published", {"slug" => "about"})
    expect { job.perform_now }.not_to have_enqueued_job(described_class)
    expect(ids.uniq).to eq([job.job_id])
  end

  it "does nothing for a webhook that no longer exists" do
    expect { described_class.perform_now(0, "page.published", {}) }.not_to raise_error
  end

  it "still runs under its old name, for deliveries queued before the rename" do
    expect(DeliverWebhookJob.superclass).to eq(described_class)
  end
end
