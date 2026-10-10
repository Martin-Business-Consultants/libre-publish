# frozen_string_literal: true

# The record's other languages: [{locale, path}], for hreflang and a language
# switcher. Paths carry their locale prefix as the site serves them.
json.translations((record.translation_group ? record.translation_group.members.where(status: "published").where.not(id: record.id).to_a : []).map { |sibling|
  {locale: sibling.locale, path: sibling.public_path}
})
