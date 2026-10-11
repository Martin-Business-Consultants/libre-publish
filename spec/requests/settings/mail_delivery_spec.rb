# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Settings › Email delivery", type: :request do
  let(:admin) { create(:user) }
  let(:reader) { create(:user, admin: false, role: create(:role, permissions: %w[settings:read])) }

  before { sign_in_as admin }

  it "saves the SMTP server, keeps the password encrypted and unshown, and keeps it when left blank" do
    get settings_mail_delivery_path
    expect(response.body).to include("SMTP server", "Send test email")

    patch settings_mail_delivery_path, params: {mail_delivery: {address: "smtp.example.com", port: "", security: "ssl",
      user_name: "sarah@example.com", password: "s3cret-pw", authentication: "login"}}
    expect(response).to redirect_to(settings_mail_delivery_path)
    expect(MailDelivery.password).to eq("s3cret-pw")
    expect(Setting.get("mail_delivery")).not_to have_key("password")

    patch settings_mail_delivery_path, params: {mail_delivery: {address: "smtp.example.com", password: ""}}
    expect(MailDelivery.password).to eq("s3cret-pw")

    get settings_mail_delivery_path
    expect(response.body).not_to include("s3cret-pw")
    expect(response.body).to include("Saved — leave blank to keep")

    expect(MailDelivery.smtp_options).to include(address: "smtp.example.com", port: 465, tls: true,
      user_name: "sarah@example.com", password: "s3cret-pw", authentication: :login)
  end

  it "sends every email through it once a host is set, and the install's server until then" do
    allow(ApplicationMailer).to receive(:delivery_method).and_return(:smtp)
    allow_any_instance_of(ApplicationMailer).to receive(:delivery_method).and_return(:smtp)
    mail = UserMailer.with(user: admin).password_reset
    expect(mail.delivery_method.settings[:address]).not_to eq("smtp.example.com")

    Setting.set("mail_delivery", {"address" => "smtp.example.com", "security" => "starttls"})
    mail = UserMailer.with(user: admin).password_reset
    expect(mail.delivery_method.settings).to include(address: "smtp.example.com", port: 587, enable_starttls: true)
  end

  it "sends a test email to whoever asks, and says why when it fails" do
    expect { post settings_mail_delivery_test_path }.to change { ActionMailer::Base.deliveries.size }.by(1)
    expect(ActionMailer::Base.deliveries.last.to).to eq([admin.email])
    expect(flash[:notice]).to include("Sent a test email")

    allow_any_instance_of(Mail::Message).to receive(:deliver).and_raise(Net::SMTPAuthenticationError.new(nil, message: "535 bad credentials"))
    post settings_mail_delivery_test_path
    expect(flash[:alert]).to include("didn't send", "535")
  end

  it "isn't the sender's place: that's Settings › Forms alone" do
    get settings_general_path
    expect(response.body).not_to include("Email sender", "email_from_name")
  end

  it "takes settings:write to change" do
    sign_in_as reader
    patch settings_mail_delivery_path, params: {mail_delivery: {address: "evil.example.com"}}
    expect(MailDelivery.configured?).to be(false)
  end
end
