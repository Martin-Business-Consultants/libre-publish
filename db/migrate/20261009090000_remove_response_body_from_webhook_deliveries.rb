# frozen_string_literal: true

# A delivery keeps its status, timing and error, not what the receiver sent
# back: a body could be anything the URL answered with, including what a
# webhook pointed inside the network was made to return.
class RemoveResponseBodyFromWebhookDeliveries < ActiveRecord::Migration[8.1]
  def change
    remove_column :webhook_deliveries, :response_body, :text
  end
end
