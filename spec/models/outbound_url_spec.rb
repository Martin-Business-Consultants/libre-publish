# frozen_string_literal: true

require "rails_helper"

RSpec.describe OutboundUrl do
  def resolving(*addresses)
    described_class.resolver = ->(_host) { addresses }
  end

  describe ".check!" do
    {
      "loopback"               => "127.0.0.1",
      "RFC 1918 (10/8)"        => "10.1.2.3",
      "RFC 1918 (172.16/12)"   => "172.20.0.1",
      "RFC 1918 (192.168/16)"  => "192.168.1.1",
      "cloud metadata"         => "169.254.169.254",
      "carrier-grade NAT"      => "100.64.0.1",
      "unspecified"            => "0.0.0.0",
      "multicast"              => "224.0.0.1",
      "IPv6 loopback"          => "::1",
      "IPv6 unique local"      => "fd00::1",
      "IPv6 link-local"        => "fe80::1",
      "IPv4-mapped loopback"   => "::ffff:127.0.0.1",
      "IPv4-mapped metadata"   => "::ffff:169.254.169.254"
    }.each do |name, address|
      it "refuses a host that resolves to #{name} (#{address})" do
        resolving(address)

        expect { described_class.check!("https://hooks.example.com/in") }.to raise_error(OutboundUrl::Unsafe, /private or local/)
      end
    end

    it "refuses an IP literal in the URL without asking DNS" do
      described_class.resolver = ->(_host) { raise "DNS asked" }

      expect { described_class.check!("http://127.0.0.1:3000/x") }.to raise_error(OutboundUrl::Unsafe)
      expect { described_class.check!("http://[::1]/x") }.to raise_error(OutboundUrl::Unsafe)
    end

    it "takes a public address, and the public one when a name answers with both" do
      resolving("10.0.0.5", "203.0.113.7")

      uri, address = described_class.check!("https://hooks.example.com/in")

      expect(uri.host).to eq("hooks.example.com")
      expect(address).to eq("203.0.113.7")
    end

    it "refuses what isn't an http(s) URL, and a host that doesn't resolve" do
      expect { described_class.check!("ftp://example.com") }.to raise_error(OutboundUrl::Unsafe, /http\(s\)/)
      expect { described_class.check!("https://") }.to raise_error(OutboundUrl::Unsafe, /http\(s\)/)

      resolving
      expect { described_class.check!("https://nowhere.example.com") }.to raise_error(OutboundUrl::Unsafe, /doesn't resolve/)
    end

    it "lets an install allow its own network with CMS_ALLOW_PRIVATE_WEBHOOKS" do
      resolving("10.0.0.5")

      with_env("CMS_ALLOW_PRIVATE_WEBHOOKS" => "true") do
        expect(described_class.check!("http://ci.internal/hook").last).to eq("10.0.0.5")
      end
      with_env("CMS_ALLOW_PRIVATE_WEBHOOKS" => "false") do
        expect { described_class.check!("http://ci.internal/hook") }.to raise_error(OutboundUrl::Unsafe)
      end
    end

    it "allows private addresses while developing unless told not to" do
      resolving("127.0.0.1")
      allow(Rails.env).to receive(:development?).and_return(true)

      with_env("CMS_ALLOW_PRIVATE_WEBHOOKS" => nil) do
        expect(described_class.check!("http://localhost:4321/_cms/webhook").last).to eq("127.0.0.1")
      end
    end
  end

  describe ".connect" do
    it "pins the connection to the address it checked, so a second lookup can't move it" do
      answers = [["203.0.113.7"], ["127.0.0.1"]]
      described_class.resolver = ->(_host) { answers.shift || ["127.0.0.1"] }

      uri, http = described_class.connect("https://hooks.example.com/in", open_timeout: 1, read_timeout: 1)

      expect(uri.host).to eq("hooks.example.com")
      expect(http.address).to eq("hooks.example.com")
      expect(http.ipaddr).to eq("203.0.113.7")
      expect(http.use_ssl?).to be(true)
    end
  end

  describe ".problem_with" do
    it "names a private address, and lets a name that doesn't resolve yet through" do
      resolving("192.168.0.10")
      expect(described_class.problem_with("https://router.example.com")).to match(/private or local/)

      resolving
      expect(described_class.problem_with("https://not-live-yet.example.com")).to be_nil
      expect(described_class.problem_with("not a url")).to match(/http\(s\)/)
    end
  end
end
