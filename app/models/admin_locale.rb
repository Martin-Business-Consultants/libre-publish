# frozen_string_literal: true

# The language the admin is in: a person's own (Settings › Account), else
# the workspace's (Settings › General), else English. Only the admin's own
# words: content has its own locales (Page#locale), and the website and the
# API are untouched.
#
# The admin's text is English in the views, translated where it's shown
# (AdminLocale.translate, the `tx` helper) from config/locales/admin/*.yml,
# keyed by the English itself:
#
#   es:
#     admin_text:
#       "Pages": "Páginas"
#       "Entry in %{name}": "Entrada en %{name}"
#
# A string without a translation shows in English, so a language can grow a
# screen at a time. A plugin adds its own the same way, from its engine's
# config/locales.
module AdminLocale
  LANGUAGES = {"en" => "English", "es" => "Español", "fr" => "Français", "de" => "Deutsch"}.freeze
  DEFAULT = "en"
  SETTING_FIELD = "admin_locale"

  module_function

  def workspace = Setting.get("general")[SETTING_FIELD].presence_in(LANGUAGES.keys) || DEFAULT

  def for(user) = user&.locale.presence_in(LANGUAGES.keys) || workspace

  def translate(english, locale = I18n.locale, **values)
    text = english.to_s
    unless locale.to_s == DEFAULT
      table = I18n.t(:admin_text, locale: locale, default: {})
      text = table[text.to_sym].presence || text if table.is_a?(Hash)
    end
    values.empty? ? text : format(text.gsub(/%(?!\{)/, "%%"), **values)
  end
end
