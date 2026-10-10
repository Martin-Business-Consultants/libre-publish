# frozen_string_literal: true

# The core's view of the media library, whichever plugin provides it
# (Cms::Plugins.provide :media, a provider — the Media plugin's, by default).
# The core has "asset" fields — a value is an asset's id — and reads what
# they point at through here: an asset field's thumbnail, ?resolve=assets in
# the API, the Branding logo and favicon. With no provider on, every answer is
# nil or empty, an asset field takes an id by hand, and Branding has no logo.
#
# A provider answers:
#   find(id)                 an asset, or nil
#   upload(file, folder:)    a new asset from an uploaded file
#   resolve(kind, records)   {id => summary} for the API (kind: :pages, :entries, :globals)
#   images_without_alt       [images, those used in content without alt text]
# and an asset answers title, alt, image?, content_type, updated_at, url and
# thumb_url(size). A provider's picker, rendered in the content_form slot,
# hands a pick to an asset field as a window "asset-picker:picked" event
# ({field, id, name, thumb}); an asset field opens it as the dialog
# #asset_picker_dialog, with the field's id in its data-for-field.
module MediaLibrary
  module_function

  def provider = Cms::Plugins.provided(:media)

  def available? = !provider.nil?

  def find(id)
    provider&.find(id) if id.present?
  end

  def upload(file, folder:)
    provider&.upload(file, folder: folder)
  end

  # nil without a provider, so the API leaves `assets` out.
  def resolve(kind, records)
    provider&.resolve(kind, records)
  end

  def images_without_alt
    provider&.images_without_alt
  end
end
