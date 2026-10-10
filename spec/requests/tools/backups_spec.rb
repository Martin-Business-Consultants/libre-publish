# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

# Tools › Backup. Its API half is /api/tools/backup (the `cms` CLI's).
RSpec.describe "Tools › Backup", type: :request do
  include ActiveJob::TestHelper

  let(:admin) { create(:user) }

  before { sign_in_as admin }

  describe "backup" do
    around do |example|
      Dir.mktmpdir do |dir|
        ENV["CMS_BACKUP_DIR"] = dir
        example.run
      ensure
        ENV.delete("CMS_BACKUP_DIR")
      end
    end

    it "says what a backup holds and lists the automatic ones" do
      File.write(File.join(ENV["CMS_BACKUP_DIR"], "cms-data-20260901-120000.tar.gz"), "x" * 2048)
      File.write(File.join(ENV["CMS_BACKUP_DIR"], "unrelated.txt"), "no")
      Page.create!(slug: "about", title: "About", status: "draft", locale: "en")

      get tools_backup_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("1 pages", "cms-data-20260901-120000.tar.gz", "2 KB")
      expect(response.body).not_to include("unrelated.txt")
    end

    it "downloads an automatic backup, but only one that's listed" do
      File.write(File.join(ENV["CMS_BACKUP_DIR"], "cms-data-20260901-120000.tar.gz"), "archive")

      get tools_backup_archive_path("cms-data-20260901-120000.tar.gz")
      expect(response.body).to eq("archive")
      expect(response.headers["Content-Disposition"]).to include("attachment")
      expect(AuditLog.last.action).to eq("data_backup.downloaded")

      get tools_backup_archive_path("cms-data-20260902-120000.tar.gz")
      expect(response).to have_http_status(:not_found)
    end

    it "downloads a backup of the site now" do
      post tools_backup_path

      expect(response.media_type).to eq("application/gzip")
      expect(AuditLog.last.action).to eq("site_backup.exported")
    end

    it "is refused without tools:use" do
      sign_in_as create(:user, admin: false, role: create(:role, permissions: %w[pages:read]))

      get tools_backup_path

      expect(response).to have_http_status(:redirect)
    end
  end
end
