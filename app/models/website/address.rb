# frozen_string_literal: true

# What the website shows at a path: the inverse of PubliclyAddressable's
# public_path. "/" is the home page, "/about" a page by its path, and
# "/<collection>/<slug>" an entry, unless a page owns that path. Only live
# records, unless `drafts:` (an editor's preview).
#
#   Website::Address.new("/services/garden-consultation").record
#   # => #<CollectionEntry slug: "garden-consultation" …>
class Website::Address
  attr_reader :path

  def initialize(path, drafts: false)
    @path = path.to_s.delete_suffix("/").presence || "/"
    @drafts = drafts
  end

  def record
    return @record if defined?(@record)

    @record = page || entry
  end

  # The redirect rule for the path, from Tools › Redirects (counted).
  def redirect = Redirect.resolve(path)

  # Where the admin page the path was before the admin moved under /cms
  # (1.8) is now: "/pages/home/edit" is "/cms/pages/home/edit". Nil for any
  # other path, so bookmarks and links in old emails keep working.
  def admin_path
    moved = "/#{Cms::PATH}#{path}"
    route = Rails.application.routes.recognize_path(moved, method: :get)
    moved unless route[:controller].to_s.start_with?("website/")
  rescue ActionController::RoutingError
    nil
  end

  private

  def page
    scope(Page).find_by(path: page_path, locale: Page.default_locale)
  end

  def entry
    collection_slug, slug, *rest = segments
    return if slug.nil? || rest.any?

    collection = Collection.find_by(slug: collection_slug)
    collection && scope(collection.entries).find_by(slug: slug)
  end

  def page_path = path == "/" ? "home" : segments.join("/")

  def segments = path.delete_prefix("/").split("/")

  def scope(records) = @drafts ? records : records.live
end
