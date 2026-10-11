# frozen_string_literal: true

require "rails_helper"

# The admin in a person's language (AdminLocale): their own (Settings ›
# Account), else the workspace's (Settings › General), else English; the
# English shows wherever a translation is missing, and the website and the
# content are untouched.
RSpec.describe "The admin's language", type: :request do
  let(:user) { create(:user) }

  it "follows the person's choice, else the workspace's, and leaves the website in its own" do
    sign_in_as user
    get dashboard_path
    expect(response.body).to include(%(<html lang="en">), ">Settings<")

    Setting.set("general", "admin_locale" => "fr")
    get dashboard_path
    expect(response.body).to include(%(<html lang="fr">), "Réglages", "Tableau de bord")

    patch settings_profile_path, params: {name: user.name, locale: "es"}
    expect(user.reload.locale).to eq("es")
    get settings_path
    expect(response.body).to include(%(<html lang="es">), "Ajustes", "Espacio de trabajo", "Cerrar sesión")
    expect(I18n.locale).to eq(:en)

    patch settings_profile_path, params: {name: user.name, locale: "xx"}
    expect(user.reload.locale).to be_nil
  end

  it "shows the sign-in page in the workspace's language" do
    Setting.set("general", "admin_locale" => "de")
    get sign_in_path
    expect(response.body).to include("Bei deinem Konto anmelden", "Passwort vergessen?")
  end

  it "keeps a translation's placeholders, and shows the English where one is missing" do
    expect(AdminLocale.translate("Howdy, %{name}", :es, name: "Ana 100%")).to eq("Hola, Ana 100%")
    expect(AdminLocale.translate("Nothing translates this", :de)).to eq("Nothing translates this")
    expect(AdminLocale.translate("Version %{version} available", :en, version: "2.0")).to eq("Version 2.0 available")
  end

  it "has every language say the same things, with the same placeholders" do
    tables = AdminLocale::LANGUAGES.keys.excluding("en").index_with { I18n.t(:admin_text, locale: it) }
    keys = tables.values.map(&:keys)
    expect(keys.uniq.size).to eq(1)
    tables.each_value do |table|
      table.each { |english, text| expect(text.scan(/%\{\w+\}/).sort).to eq(english.to_s.scan(/%\{\w+\}/).sort), english.to_s }
    end
  end
end
