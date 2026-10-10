# frozen_string_literal: true

# Daily: is there a newer CMS release (UpdateCheck), or plugin or theme
# release (UpdateCheck::Plugins)? And settle any update
# that finished or went quiet while nobody had Settings › Updates open.
class UpdateCheckJob < ApplicationJob
  queue_as :default

  def perform
    if UpdateCheck.checking?
      UpdateCheck.check_now
      UpdateCheck::Plugins.check_now
    end
  ensure
    Upgrade.settle_running
  end
end
