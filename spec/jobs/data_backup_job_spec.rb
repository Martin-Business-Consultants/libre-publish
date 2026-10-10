# frozen_string_literal: true

require "rails_helper"

RSpec.describe DataBackupJob do
  it "takes the nightly backup" do
    backup = instance_double(Cms::DataBackup, nightly: "/data/backups/cms-data-x.tar.gz")
    allow(Cms::DataBackup).to receive(:for_install).and_return(backup)

    described_class.perform_now

    expect(backup).to have_received(:nightly)
  end

  it "takes none when the install turned it off" do
    allow(Cms::DataBackup).to receive(:for_install)
    ENV["CMS_BACKUP_NIGHTLY"] = "false"

    described_class.perform_now

    expect(Cms::DataBackup).not_to have_received(:for_install)
  ensure
    ENV.delete("CMS_BACKUP_NIGHTLY")
  end

  it "is scheduled nightly" do
    schedule = YAML.load_file(Rails.root.join("config/recurring.yml"), aliases: true).dig("production", "data_backup")

    expect(schedule).to include("class" => "DataBackupJob", "schedule" => "every day at 2am")
  end
end
