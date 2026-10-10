# frozen_string_literal: true

require "rails_helper"

RSpec.describe Session do
  let(:user) { create(:user) }

  it "starts seen, and expires LIFETIME after sign-in" do
    session = user.sessions.create!

    expect(session.last_seen_at).to be_within(1.second).of(Time.current)
    expect(session.expires_at).to be_within(1.second).of(Session::LIFETIME.from_now)
  end

  describe "#expired?" do
    it "is live while used and young" do
      session = user.sessions.create!
      expect(session.expired?).to be(false)
    end

    it "ends LIFETIME after sign-in however much it's used" do
      session = user.sessions.create!(created_at: (Session::LIFETIME + 1.minute).ago)
      session.update_column(:last_seen_at, Time.current)
      expect(session.expired?).to be(true)
    end

    it "ends after IDLE_TIMEOUT unused" do
      session = user.sessions.create!
      session.update_column(:last_seen_at, (Session::IDLE_TIMEOUT + 1.minute).ago)
      expect(session.expired?).to be(true)
    end
  end

  describe "#seen!" do
    it "records use at most once per SEEN_EVERY" do
      session = user.sessions.create!
      session.update_column(:last_seen_at, 10.minutes.ago)
      expect { session.seen! }.not_to(change { session.reload.last_seen_at })

      session.update_column(:last_seen_at, 2.hours.ago)
      session.seen!
      expect(session.reload.last_seen_at).to be_within(1.second).of(Time.current)
    end
  end

  it ".expired finds the ended sessions only" do
    live = user.sessions.create!
    old = user.sessions.create!(created_at: (Session::LIFETIME + 1.day).ago)
    idle = user.sessions.create!
    idle.update_column(:last_seen_at, (Session::IDLE_TIMEOUT + 1.day).ago)

    expect(Session.expired).to contain_exactly(old, idle)
    expect(Session.expired).not_to include(live)
  end
end
