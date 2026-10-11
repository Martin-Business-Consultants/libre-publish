# frozen_string_literal: true

# The admin's words in the admin's language (AdminLocale): tx("Pages"),
# tx("Entry in %{name}", name: collection.name). The English is the key and
# what shows without a translation.
module AdminTextHelper
  def tx(english, **values) = AdminLocale.translate(english, **values)
end
