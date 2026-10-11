# frozen_string_literal: true

require "rails_helper"

# users:write, roles:write and settings:write each let someone hand out
# capabilities; none lets them hand out more than they hold (Granting).
RSpec.describe "Handing out no more than you hold", type: :request do
  let(:manager_role) { create(:role, permissions: %w[users:read users:write roles:read roles:write]) }
  let(:manager) { create(:user, admin: false, role: manager_role) }
  let(:admin) { create(:user) }

  before { sign_in_as manager }

  it "can't make anyone, themselves included, an admin, or touch an admin's account" do
    patch user_path(manager), params: {user: {role_id: Role.system_admin.id}}
    expect(manager.reload.role).to eq(manager_role)

    patch user_path(admin), params: {user: {password: "Hijacked1!2@3#", password_confirmation: "Hijacked1!2@3#"}}
    expect(admin.reload.authenticate("Hijacked1!2@3#")).to be(false)

    post users_path, params: {user: {name: "Sock", email: "sock@x.test", password: "Secret1*3*5*", password_confirmation: "Secret1*3*5*", role_id: Role.system_admin.id}}
    expect(User.exists?(email: "sock@x.test")).to be(false)
  end

  it "can't write a role holding more than they do" do
    post roles_path, params: {role: {name: "Root", permissions: [Permissions::WILDCARD]}}
    expect(Role.exists?(name: "Root")).to be(false)

    post roles_path, params: {role: {name: "Publisher", permissions: %w[pages:read pages:publish]}}
    expect(Role.exists?(name: "Publisher")).to be(false)

    post roles_path, params: {role: {name: "Helpers", permissions: %w[users:read]}}
    expect(Role.exists?(name: "Helpers")).to be(true)
  end
end
