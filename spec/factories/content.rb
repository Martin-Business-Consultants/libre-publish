# frozen_string_literal: true

# The content records most specs build. Each is valid as it stands, a draft
# where it has a status; override what a spec is about:
#
#   create(:page, status: "published", parent: create(:page))
#   create(:collection_entry, collection: create(:collection, enable_blocks: true))
FactoryBot.define do
  factory :page do
    sequence(:slug) { |n| "page-#{n}" }
    title { slug.titleize }
    status { "draft" }
    locale { "en" }
  end

  factory :collection do
    sequence(:slug) { |n| "collection-#{n}" }
    name { slug.titleize }
    schema { {"fields" => []} }
  end

  factory :collection_entry do
    collection
    sequence(:slug) { |n| "entry-#{n}" }
    title { slug.titleize }
    status { "draft" }
    locale { "en" }
  end

  factory :global do
    sequence(:slug) { |n| "global_#{n}" }
    name { slug.humanize }
    schema { {"fields" => []} }
    data { {} }
  end

  factory :webhook do
    sequence(:name) { |n| "Webhook #{n}" }
    url { "https://hooks.example.com/in" }
    events { ["page.published"] }
  end

  factory :redirect do
    sequence(:source_path) { |n| "/old-#{n}" }
    destination_url { "/new" }
    status_code { 301 }
  end
end
