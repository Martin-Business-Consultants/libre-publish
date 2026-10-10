# frozen_string_literal: true

require "rails_helper"

RSpec.describe VersionPruneJob do
  it "prunes pages' and entries' versions" do
    allow(PageVersion).to receive(:prune)
    allow(CollectionEntryVersion).to receive(:prune)

    described_class.perform_now

    expect(PageVersion).to have_received(:prune)
    expect(CollectionEntryVersion).to have_received(:prune)
  end

  it "is scheduled nightly" do
    schedule = YAML.load_file(Rails.root.join("config/recurring.yml"), aliases: true).dig("production", "version_prune")

    expect(schedule).to include("class" => "VersionPruneJob", "schedule" => "every day at 3:30am")
  end
end
