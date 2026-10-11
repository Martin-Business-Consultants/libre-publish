# frozen_string_literal: true

# What the update progress modal (layouts/shared/update_progress) shows: each
# CMS update (Upgrade) and plugin or theme change (PluginChange) under way,
# with how far along it is, and how the ones the page was watching ended.
# Read by anyone signed in, since an update restarts the CMS under everyone.
#
#   UpdateProgress.new(watching: %w[upgrade-3]).items
class UpdateProgress
  Item = Data.define(:id, :title, :percent, :step, :status, :message)

  def self.running? = Upgrade.running.exists? || PluginChange.running.exists?

  # watching: the ids ("upgrade-3", "plugin_change-5") the page saw running.
  def initialize(watching: [])
    @watching = Array(watching).grep(/\A(upgrade|plugin_change)-\d+\z/).group_by { it[/\A\w+(?=-)/] }
      .transform_values { |ids| ids.map { it[/\d+\z/].to_i } }
  end

  # Settles what has finished first, as Settings › Updates and Plugins do.
  def items
    Upgrade.settle_running
    PluginChange.reconcile

    upgrades = Upgrade.running.or(Upgrade.where(id: @watching["upgrade"])).ordered.map do |upgrade|
      item("upgrade", upgrade, "Updating the CMS to #{upgrade.to_version}")
    end
    changes = PluginChange.running.or(PluginChange.where(id: @watching["plugin_change"])).ordered.map do |change|
      item("plugin_change", change, change.summary)
    end
    upgrades + changes
  end

  private

  def item(kind, record, title)
    percent, step = record.progress
    Item.new(id: "#{kind}-#{record.id}", title: title, percent: percent, step: step, status: record.status,
      message: (record.message if record.failed?))
  end
end
