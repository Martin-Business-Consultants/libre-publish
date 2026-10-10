# frozen_string_literal: true

# What a checklist is made of: a check says whether it passes (`ok`: true,
# false, or nil when it's yours to judge or doesn't apply), what it's about,
# and where to fix it — in the admin (`href`) and from the CLI (`cli`).
# SiteHealth is a list of these, shown in Docs, at /api/site_health and by
# `cms site-health`.
module Checklist
  Check = Data.define(:key, :group, :title, :detail, :ok, :href, :cli) do
    def as_json(*) = to_h.transform_keys(&:to_s)
  end

  module_function

  # {total:, passing:, failing:, ready:} over the checks that apply.
  def summary(list)
    applicable = list.reject { it.ok.nil? }
    passing = applicable.count(&:ok)
    {total: applicable.size, passing: passing, failing: applicable.size - passing, ready: passing == applicable.size}
  end
end
