# frozen_string_literal: true

# Filters and actions, WordPress's two kinds of hook (docs/plugins.md, Hooks).
#
# A filter changes a value the core is about to use: each plugin's filter on
# that hook gets the value and returns it, changed or not, lowest priority
# first. An action runs on something that happened: every "<event>.cms"
# notification (page.published, entry.created, submission.created, …).
# Either is skipped while its plugin is off, and one that raises is
# reported (Rails.error) and passed over, so a plugin's bug never takes the
# page down.
#
#   Cms::Plugins.filter(:seo_plus, "website.seo", priority: 20) { |seo, record:| seo.merge(title: "#{seo[:title]} | Acme") }
#   Cms::Plugins.on(:hello, "page.published") { |payload| Hello::Greeting.create!(…) }
#
#   Cms::Hooks.apply("website.seo", seo, record: page)   # the core, where a value can be changed
#   Cms::Hooks.run("theme.switched", key: :healing)      # the core or a plugin, announcing something
module Cms
  module Hooks
    Hook = Struct.new(:plugin, :callable, :priority, :order, keyword_init: true)

    # The hooks the core applies, with what each passes (docs/plugins.md).
    FILTERS = {
      "website.seo" => "the <head> tags' values ({title:, description:, canonical:, image:, robots:}); record:",
      "website.block" => "a block's HTML; block:",
      "website.markdown" => "Markdown drawn as HTML; text:",
      "website.head" => "HTML for the end of <head>, after the theme's; request:",
      "website.body" => "HTML for the end of <body>, after the theme's; request:",
      "sitemap.entries" => "the sitemap's rows (Sitemap::Entry)",
      "website.cache_version" => "what a cached website page depends on (a list; add a stamp of what your plugin draws into pages)"
    }.freeze

    mattr_reader :filters, default: Hash.new { |hash, name| hash[name] = [] }
    mattr_reader :actions, default: Hash.new { |hash, name| hash[name] = [] }

    module_function

    def add_filter(plugin, name, priority:, callable:) = add(filters, plugin, name, priority, callable)
    def add_action(plugin, event, priority:, callable:) = add(actions, plugin, event, priority, callable)

    # Everything a plugin hooked, dropped as it registers again (a code reload).
    def forget(plugin)
      [filters, actions].each { |hooks| hooks.each_value { |list| list.reject! { it.plugin == plugin } } }
    end

    def apply(name, value, **context)
      active(filters[name.to_s]).reduce(value) do |current, hook|
        hook.callable.call(current, **context)
      rescue StandardError => error
        report(error, hook, name)
        current
      end
    end

    # Announces an action of a plugin's own, or the core's, as "<name>.cms".
    def run(name, **payload) = ActiveSupport::Notifications.instrument("#{name}.cms", payload)

    # Every "<event>.cms" notification reaches the actions on that event.
    # Subscribed once, at boot; through the constant, so a code reload's
    # Cms::Hooks (and the actions registered on it) is the one that hears.
    def subscribe!
      ActiveSupport::Notifications.subscribe(/\.cms\z/) { |event| Cms::Hooks.dispatch(event.name.delete_suffix(".cms"), event.payload) }
    end

    def dispatch(name, payload)
      active(actions[name]).each do |hook|
        hook.callable.call(payload)
      rescue StandardError => error
        report(error, hook, name)
      end
    end

    def add(hooks, plugin, name, priority, callable)
      list = hooks[name.to_s]
      list << Hook.new(plugin: plugin.to_sym, callable: callable, priority: priority, order: list.size)
    end

    def active(list) = list.select { Cms::Plugins.enabled?(it.plugin) }.sort_by { [it.priority, it.order] }

    def report(error, hook, name)
      Rails.error.report(error, handled: true, context: {plugin: hook.plugin, hook: name})
    end
  end
end
