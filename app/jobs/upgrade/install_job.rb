# frozen_string_literal: true

# Installs a release in place (Upgrade::InPlace) away from the request that
# asked: the download takes a while.
class Upgrade::InstallJob < ApplicationJob
  def perform(upgrade)
    upgrade.runner.install if upgrade.running? && upgrade.via == "in_place"
  end
end
