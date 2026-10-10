# frozen_string_literal: true

# The core is slimmed to content in, JSON out. Gone: review requests,
# revisions (pending changes), recommendations, recurring tasks and the
# checklists, and the Agents, AI, Consent & Scripts, Importers and Local
# Marketing plugins. Their tables, settings and capabilities go with them.
# Forms and Commerce moved to their own repositories and keep their tables.
class RemoveWorkflowAndDroppedPlugins < ActiveRecord::Migration[8.1]
  # Dependents before what they point at.
  TABLES = %w[
    recommendations revisions review_requests recurring_tasks
    agent_runs swarm_members swarms swarm_templates content_scopes agents agent_templates
    reports scripts
  ].freeze

  SETTING_KEYS = %w[onboarding ai consent citations marketing reporting site_audit].freeze

  CAPABILITY_PREFIXES = %w[recommendations agents reports scripts consent].freeze

  def up
    TABLES.each { |table| drop_table table, if_exists: true }

    execute "DELETE FROM settings WHERE key IN (#{SETTING_KEYS.map { connection.quote(it) }.join(", ")})"

    select_rows("SELECT id, permissions FROM roles").each do |id, permissions|
      list = JSON.parse(permissions.to_s) rescue next
      kept = list.reject { |capability| CAPABILITY_PREFIXES.include?(capability.to_s.split(":").first) }
      next if kept == list

      execute "UPDATE roles SET permissions = #{connection.quote(kept.to_json)} WHERE id = #{id.to_i}"
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
