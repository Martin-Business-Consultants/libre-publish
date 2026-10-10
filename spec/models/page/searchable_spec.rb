# frozen_string_literal: true

require "rails_helper"

RSpec.describe Page::Searchable do
  def found(term) = Page.search_index_ids(term)

  it "keeps the search index in step with the page, and leaves the trash out" do
    page = Page.create!(slug: "about", title: "About", status: "draft", locale: "en")
    expect(found("About")).to eq([page.id])

    page.update!(title: "Our history")
    expect(found("history")).to eq([page.id])
    expect(found("istor")).to eq([page.id]) # any part of a word
    expect(found("About")).to eq([page.id]) # its path, about

    page.trash
    expect(found("history")).to be_empty

    page.restore!
    expect(found("history")).to eq([page.id])

    page.destroy_permanently!
    expect(found("history")).to be_empty
  end
end
