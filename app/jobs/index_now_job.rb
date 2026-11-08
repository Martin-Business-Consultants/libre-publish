# frozen_string_literal: true

# Tells IndexNow's search engines about pages that changed
# (IndexNow.submit_now).
class IndexNowJob < ApplicationJob
  queue_as :default

  def perform(urls)
    IndexNow.submit_now(urls)
  end
end
