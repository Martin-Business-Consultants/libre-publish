# frozen_string_literal: true

require "rails_helper"

RSpec.describe Redirect::Import do
  it "reads rows from an IO one at a time, numbering them as a spreadsheet does" do
    io = StringIO.new("source_path,destination_url\n/a,/b\n/c*,/d\n")
    expect(CSV).not_to receive(:parse)

    import = Redirect.import_csv(io)

    expect(import.created).to eq(1)
    expect(import.errors.map { it[:row] }).to eq([3])
  end

  it "says when a size is over the limit" do
    expect(described_class.too_big?(described_class::MAX_BYTES)).to be(false)
    expect(described_class.too_big?(described_class::MAX_BYTES + 1)).to be(true)
  end
end
