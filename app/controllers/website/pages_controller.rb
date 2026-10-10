# frozen_string_literal: true

# The public website: whatever the CMS has at an address, drawn by the theme
# (Website.theme). A page renders website/pages/show; an entry renders
# website/entries/<collection>, when the theme has one (a collection it
# doesn't draw has no pages); anything else is the theme's
# website/not_found, after Tools › Redirects has had its say and an address
# the admin had before it moved under /cms (/pages) has gone there.
#
# Not an ApplicationController: visitors aren't signed in, aren't held to the
# admin's modern-browsers rule, and see only published content. An editor who
# is signed in can add ?preview to see drafts, uncached.
class Website::PagesController < ActionController::Base
  layout "website"

  # A page's ETag is its content and the theme (below), never the visitor's
  # flash or session, so every visitor shares one cached copy.
  self.etaggers = []

  before_action { prepend_view_path Website.theme.views if Website.enabled? }

  def show
    return headless unless Website.enabled?

    # One address per page: "/about/" is "/about". (The router has already
    # dropped the slash from request.path; the original keeps it.)
    path = request.original_fullpath.split("?").first
    return redirect_to(path.chomp("/") + request.query_string.then { it.empty? ? "" : "?#{it}" }, status: :moved_permanently) if path.length > 1 && path.end_with?("/")

    return markdown(path.delete_suffix(".md")) if path.end_with?(".md")
    return feed(path.delete_prefix("/").delete_suffix("/feed.xml")) if path.end_with?("/feed.xml")
    return render(plain: IndexNow.key) if path == "/#{SearchSettings.get["indexnow_key"]}.txt" && SearchSettings.get["indexnow_key"].present?

    address = Website::Address.new(request.path, drafts: previewing?)
    case address.record
    when Page then render_record "website/pages/show", page: address.record
    when CollectionEntry then render_record "website/entries/#{address.record.collection.slug}", entry: address.record
    else not_found(address)
    end
  end

  # /robots.txt (Website::Robots): served with a theme or without, so the
  # admin and the API stay out of search either way.
  def robots
    expires_in 1.hour, public: true
    render plain: Website::Robots.new(base_url).to_s
  end

  # /llms.txt: the site's index for AI readers (WebsiteMarkdownHelper).
  def llms
    return head(:not_found) unless Website.enabled?

    expires_in 1.hour, public: true
    render plain: helpers.website_llms_txt(Sitemap.new.entries), content_type: "text/markdown"
  end

  private

  # A page or entry as Markdown: /about.md, and /index.md for the home page.
  def markdown(path)
    address = Website::Address.new((path == "/index") ? "/" : path, drafts: previewing?)
    record = address.record
    # Only what the website has a page for (the theme draws it as HTML).
    drawn = record.is_a?(Page) || lookup_context.exists?("website/entries/#{record&.collection&.slug}", [], false, [], formats: [:html])
    return head(:not_found) unless record && drawn
    return head(:not_found) if record.seo.to_h["noindex"] && !previewing?

    expires_in 1.minute, public: true, stale_while_revalidate: 1.day unless previewing?
    if previewing? || stale?(etag: [Website.cache_version, record, :markdown], public: true)
      render plain: helpers.website_markdown_document(record), content_type: "text/markdown"
    end
  end

  # /<collection>/feed.xml: its newest published entries, as RSS, for a
  # collection the theme draws.
  def feed(slug)
    collection = Collection.find_by(slug: slug)
    return head(:not_found) unless collection && lookup_context.exists?("website/entries/#{slug}", [], false, [], formats: [:html])

    entries = collection.entries.live.order(published_at: :desc, id: :desc).limit(20).to_a
    expires_in 5.minutes, public: true
    if stale?(etag: [Website.cache_version, :feed, slug], public: true)
      render plain: helpers.website_feed_xml(collection, entries), content_type: "application/rss+xml"
    end
  end

  def base_url = Setting.get("general")["site_base_url"].presence&.chomp("/") || request.base_url

  # A published page can be cached anywhere (the browser, Thruster,
  # Cloudflare) and revalidates against the content and the theme; a preview
  # never is.
  def render_record(template, **locals)
    return not_found(Website::Address.new(request.path)) unless template_exists?(template)

    if previewing?
      response.headers["Cache-Control"] = "private, no-store"
      render template, locals:
    else
      expires_in 1.minute, public: true, stale_while_revalidate: 1.day
      render(template, locals:) if stale?(etag: [Website.cache_version, locals.values.first], public: true)
    end
  end

  # A headless install has no site: an old admin address goes to /cms, and
  # anything else is the plain 404 it always was.
  def headless
    if (moved = Website::Address.new(request.path).admin_path)
      redirect_to moved_with_query(moved), status: :moved_permanently
    else
      render file: Rails.public_path.join("404.html"), status: :not_found, layout: false
    end
  end

  def not_found(address)
    if (found = address.redirect)
      redirect_to found[:destination], status: found[:status], allow_other_host: true
    elsif (moved = address.admin_path)
      redirect_to moved_with_query(moved), status: :moved_permanently
    elsif template_exists?("website/not_found")
      render "website/not_found", status: :not_found
    else
      head :not_found
    end
  end

  def moved_with_query(path) = request.query_string.empty? ? path : "#{path}?#{request.query_string}"

  # Only for someone signed in to the admin, and only when they ask.
  def previewing?
    return @previewing if defined?(@previewing)

    @previewing = params.key?(:preview) && Session.find_by_id(cookies.signed[:session_token]).then { it && !it.expired? }
  end
end
