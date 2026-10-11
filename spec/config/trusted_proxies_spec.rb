# frozen_string_literal: true

require "rails_helper"

RSpec.describe TrustedProxies do
  # The address Rails gives a request that came through kamal-proxy (on the
  # Docker network) from a Cloudflare edge, for a visitor at 198.51.100.7.
  def remote_ip(proxies, forwarded_for: "198.51.100.7, 162.158.1.1")
    env = Rack::MockRequest.env_for("/", "REMOTE_ADDR" => "172.18.0.2", "HTTP_X_FORWARDED_FOR" => forwarded_for)
    ActionDispatch::RemoteIp.new(->(e) { [200, {}, [ActionDispatch::Request.new(e).remote_ip]] }, true, proxies).call(env).last.first
  end

  it "reads cloudflare as Cloudflare's ranges, alongside addresses and CIDR ranges" do
    ranges, invalid = described_class.parse(" Cloudflare, 203.0.113.0/24,10.1.2.3 ")
    expect(invalid).to be_empty
    expect(ranges.size).to eq(described_class::CLOUDFLARE.size + 2)
    expect(ranges).to include(IPAddr.new("162.158.0.0/15"), IPAddr.new("2606:4700::/32"), IPAddr.new("10.1.2.3"))
  end

  it "names what it can't read" do
    expect(described_class.parse("cloudflair, 300.1.1.1, 10.0.0.0/8").last).to eq(%w[cloudflair 300.1.1.1])
  end

  it "keeps Rails' own when none are given, and carries them when some are" do
    expect(described_class.for_rails(nil)).to be_nil
    expect(described_class.for_rails("")).to be_nil
    expect(described_class.for_rails("cloudflare")).to include(*ActionDispatch::RemoteIp::TRUSTED_PROXIES)
  end

  it "makes the visitor's address the remote IP behind Cloudflare, rather than the edge's" do
    expect(remote_ip(ActionDispatch::RemoteIp::TRUSTED_PROXIES)).to eq("162.158.1.1")
    expect(remote_ip(described_class.for_rails("cloudflare"))).to eq("198.51.100.7")
  end

  it "doesn't believe an address a visitor puts in X-Forwarded-For themselves" do
    # Straight to the server, not through Cloudflare: the last hop is the visitor's own.
    expect(remote_ip(described_class.for_rails("cloudflare"), forwarded_for: "162.158.1.1, 198.51.100.7")).to eq("198.51.100.7")
  end
end
