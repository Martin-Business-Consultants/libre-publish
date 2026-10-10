# frozen_string_literal: true

# What plugins, themes and API clients may rely on (docs/compatibility.md):
# the Ruby methods named here, with their parameters, and every route under
# /api. Within a major version none is removed and none takes a call it
# took before differently; one on its way out warns first (Cms.deprecator).
# spec/contracts/public_api_spec.rb holds the core to the snapshot of it in
# spec/fixtures/contracts/public_api.json; `bin/rails cms:public_api`
# rewrites the snapshot once an addition is meant.
module Cms
  module PublicApi
    RUBY = {
      "Cms" => {singleton: %i[version data_dir deprecator]},
      "Cms::Plugins" => {singleton: %i[
        register slot menu submenu new_item settings permissions counts manifest_section trashable
        webhook_events webhook_event_filter hold_api_writes provide provided provided_all stylesheet
        nightly minutely bootstrap api block_types field_type deploy_provider update_strategy
        enabled? tables_of
      ]},
      "Website" => {singleton: %i[register enabled? draws? render theme cache_version]},
      "WebsiteHelper" => {instance: %i[
        website_blocks website_block website_scripts website_global website_fields website_entries
        website_path website_href website_settings website_image_tag website_image website_image_url
        website_markdown website_rich_text website_plain_text website_seo_tags website_json_ld
        website_url website_javascript_tags website_form_field previewing?
      ]}
    }.freeze

    module_function

    # {"ruby" => {"Cms::Plugins.register" => [[:req, :key], [:keyreq, :name], …]}, "routes" => ["GET /api/pages", …]}
    def snapshot
      {"ruby" => ruby, "routes" => routes}
    end

    def ruby
      RUBY.flat_map do |name, kinds|
        owner = name.constantize
        kinds.flat_map do |kind, methods|
          methods.map do |method|
            found = (kind == :singleton) ? owner.method(method) : owner.instance_method(method)
            ["#{name}#{(kind == :singleton) ? "." : "#"}#{method}", found.parameters.map { |type, param| [type.to_s, param.to_s] }]
          end
        end
      end.sort.to_h
    end

    # The core's: a plugin's API is its own to keep.
    def routes
      Rails.application.routes.routes.filter_map do |route|
        path = route.path.spec.to_s.delete_suffix("(.:format)")
        verb = route.verb.presence or next
        next unless path.start_with?("/api/") && core_controller?(route.defaults[:controller])

        "#{verb} #{path}"
      end.uniq.sort
    end

    def core_controller?(name)
      klass = "#{name}_controller".camelize.safe_constantize
      klass.nil? || Cms::Plugins.owner_of(klass).nil?
    end

    # What would break a caller of `before` (a snapshot) against `now`:
    # something gone, or called differently. An addition breaks nothing.
    def breaks(before, now = snapshot)
      gone = (before["routes"] - now["routes"]).map { "route #{it} is gone" }
      before["ruby"].each do |name, params|
        current = now["ruby"][name] or (gone << "#{name} is gone") && next
        problem = incompatible(params, current) and gone << "#{name} #{problem}"
      end
      gone
    end

    # A call that worked with `old` parameters still works with `now`'s: the
    # positional ones it took, and no more required; every keyword it took
    # (or a **rest), and no new required one.
    def incompatible(old, now)
      count = ->(params, *types) { params.count { types.include?(it.first) } }
      keywords = ->(params, *types) { params.select { types.include?(it.first) }.map(&:last) }
      rest = ->(params, type) { params.any? { it.first == type } }

      if count.(now, "req") > count.(old, "req")
        "needs more arguments"
      elsif rest.(old, "rest") && !rest.(now, "rest")
        "no longer takes any number of arguments"
      elsif !rest.(now, "rest") && count.(now, "req", "opt") < count.(old, "req", "opt")
        "takes fewer arguments"
      elsif (missing = keywords.(old, "key", "keyreq") - keywords.(now, "key", "keyreq")).any? && !rest.(now, "keyrest")
        "no longer takes #{missing.join(", ")}:"
      elsif (needed = keywords.(now, "keyreq") - keywords.(old, "keyreq")).any?
        "needs #{needed.join(", ")}: now"
      elsif rest.(old, "keyrest") && !rest.(now, "keyrest")
        "no longer takes any keyword"
      end
    end
  end
end
