# frozen_string_literal: true

module UpdatesHelper
  # How this install updates, in the words of its runner (Upgrade.runners).
  def update_method_description
    Upgrade.runners[Upgrade.via]&.description || "By hand: updating from here isn’t set up"
  end

  # What to run by hand when the button isn't set up: bin/update in a plain
  # install's checkout, else Kamal from a checkout of the release.
  def manual_update_command(tag)
    if Rails.root.join(".git").exist?
      "bin/update #{tag}"
    else
      "git checkout #{tag} && bin/kamal deploy -d #{Upgrade::Github.destination.presence || "<destination>"}"
    end
  end

  # Where a running update can be followed, named for where it runs.
  def upgrade_follow_text(upgrade)
    upgrade.runner.try(:follow_text) || "Follow the update"
  end

  def upgrade_requester(upgrade)
    upgrade.requested_by&.name.presence || upgrade.requested_by&.email || "someone since removed"
  end
end
