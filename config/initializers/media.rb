# frozen_string_literal: true

# Media: the library of files and images (Asset, in folders), uploading them
# one by one or as a zip, the picker a content form's asset fields open, and
# /api/assets. Part of the core since 1.12 (a plugin, cms-media, from 1.0 to
# 1.11), still registered as one so an install keeps its switch and the
# core's media interface (MediaLibrary, Cms::Plugins.provided(:media)) can be
# served by another provider. Its plugin, where an install still has it, is
# no longer loaded (InstalledPlugins::ABSORBED).
Rails.application.config.to_prepare do
  Cms::Plugins.register :media, name: "Media", version: Cms::VERSION, author: "Libre Publish", bundled: true,
    enabled_by_default: true,
    description: "The media library: files and images in folders, uploading them one by one or as a zip, " \
                 "the picker asset fields open, and /api/assets.",
    adopt_if: -> { Asset.with_discarded.exists? }

  Cms::Plugins.provide :media, :media, -> { Media::Provider }

  Cms::Plugins.menu :media, :media, label: "Media", icon: "image", group: "Content", after: [:forms, :globals],
    path: -> { file_manager_path }, capability: "assets:read"
  Cms::Plugins.submenu :media, :media, label: "Library", path: -> { file_manager_path }, capability: "assets:read"
  Cms::Plugins.new_item :media, label: "Media", path: -> { file_manager_path(upload: 1) }, capability: "assets:write",
    after: "Global"
  Cms::Plugins.slot :content_form, :media, "media/slots/picker"
  Cms::Plugins.stylesheet :media, "media/file-manager"

  Cms::Plugins.counts :media, after: :globals, assets: -> { Asset.count }
  Cms::Plugins.trashable :media, "asset", "Asset", label: "Assets", after: "global",
    meta: ->(asset) { {filename: asset.filename, size: ActiveSupport::NumberHelper.number_to_human_size(asset.byte_size)} }

  Cms::Plugins.api :media, "/api/assets", description: "The media library: list, upload, change and delete files."
  Cms::Plugins.api :media, "/api/asset_folders", description: "Folders: create, rename and delete them by path."
  Cms::Plugins.api :media, "/api/bulk_uploads", description: "A zip of images, unpacked into a folder."
end
