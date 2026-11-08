# frozen_string_literal: true

require "rails_helper"

RSpec.describe "AuditLogs", type: :request do
  let(:user) { create(:user) }
  before { sign_in_as user }

  it "renders the audit log index" do
    AuditLog.record(action: "page.created", actor: user)
    get audit_logs_url
    expect(response).to have_http_status(:success)
  end

  it "filters in one toolbar: the action, a day's range through its end, and one search box" do
    AuditLog.record(action: "page.created", actor: user)
    AuditLog.record(action: "user.signed_in", actor: user)
    AuditLog.where(action: "user.signed_in").update_all(created_at: 2.days.ago)
    today = Date.current.iso8601

    get audit_logs_url(action_filter: "page.created", from: today, to: today)
    rows = response.body.scan(/<tr id="audit_log_\d+"/).size
    expect(rows).to eq(1)
    expect(response.body).to include("page.created")
    expect(response.body).to include('id="list_search_s"')
    expect(response.body).not_to include('name="actor"')
  end

  it "instruments page deletion via the audit helper" do
    Page.create!(slug: "scratch", title: "Scratch", status: "draft", locale: "en",
                 blocks: [], schema: {"fields" => []}, frontmatter: {}, seo: {})

    expect {
      delete page_url("scratch")
    }.to change { AuditLog.where(action: "page.deleted").count }.by(1)

    log = AuditLog.where(action: "page.deleted").last
    expect(log.actor_id).to eq(user.id)
    expect(log.target_label).to eq("Scratch")
  end

  it "blocks readers without the audit_log:read capability" do
    reader_role = create(:role, permissions: ["pages:read"])
    reader      = create(:user, admin: false, role: reader_role)
    sign_in_as reader

    get audit_logs_url
    expect(response).to redirect_to(dashboard_path)
  end
end
