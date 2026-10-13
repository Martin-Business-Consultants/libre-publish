# frozen_string_literal: true

require "rails_helper"

RSpec.describe Global::ScriptCode do
  let(:formatted) do
    %(<p>&lt;!-- Google tag (gtag.js) --&gt;<br>&lt;script async src="https://www.googletagmanager.com/gtag/js?id=G-1"&gt;&lt;/script&gt;<br>&lt;script&gt;<br>  gtag('config', 'G-1');<br>&lt;/script&gt;</p>)
  end

  it "puts a script saved as formatted text back as the code it was" do
    expect(described_class.restore(formatted)).to eq(<<~HTML.strip)
      <!-- Google tag (gtag.js) -->
      <script async src="https://www.googletagmanager.com/gtag/js?id=G-1"></script>
      <script>
        gtag('config', 'G-1');
      </script>
    HTML
  end

  it "leaves code, and text that isn't a formatted script, as it is" do
    code = %(<script>gtag("config","G-1")</script>)
    expect(described_class.restore(code)).to eq(code)
    expect(described_class.restore("<p>Hello &amp; welcome</p>")).to eq("<p>Hello &amp; welcome</p>")
    expect(described_class.restore(nil)).to be_nil
  end
end
