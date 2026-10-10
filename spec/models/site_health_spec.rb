# frozen_string_literal: true

require "rails_helper"

RSpec.describe SiteHealth do
  def check(key) = described_class.checks.find { it.key == key }

  it "finds a phone number in the content that isn't the business's" do
    Setting.set("general", phone: "(269) 555-1234")
    Page.create!(slug: "home", title: "Home", status: "published", locale: "en", frontmatter: {"cta" => "Call 269.555.1234 today"})
    expect(check("phone_consistent").ok).to be(true)

    Global.create!(slug: "footer", name: "Footer", schema: {"fields" => []}, data: {"line" => "Or call +1 (616) 555-9876"})
    result = check("phone_consistent")
    expect(result.ok).to be(false)
    expect(result.detail).to include("(616) 555-9876", "Footer")
  end

  it "looks for the pages a business must have" do
    Page.create!(slug: "privacy-policy", title: "Privacy policy", status: "published", locale: "en")
    expect(check("privacy_page").ok).to be(true)
    expect(check("terms_page").ok).to be(false)
  end
end
