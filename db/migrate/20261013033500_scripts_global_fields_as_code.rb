# frozen_string_literal: true

# The Scripts global's Head and Body were "text" fields, edited as rich text:
# a script pasted there was saved as formatted text and printed on the page
# as words (a Google tag that Google can't find). They're code fields now,
# and a script already formatted that way is put back as it was pasted.
class ScriptsGlobalFieldsAsCode < ActiveRecord::Migration[8.1]
  class Global < ActiveRecord::Base
    self.table_name = "globals"
  end

  def up
    Global.where(slug: "scripts").find_each do |global|
      schema = global.schema.deep_dup
      Array(schema&.dig("fields")).each do |field|
        Array(field["of"]).each { it["type"] = "code" if it["name"].in?(%w[head body]) && it["type"] == "text" }
      end
      data = global.data.deep_dup
      Array(data&.dig("items")).each do |item|
        next unless item.is_a?(Hash)

        %w[head body].each { |part| item[part] = ::Global::ScriptCode.restore(item[part]) if item[part].is_a?(String) }
      end
      global.update_columns(schema: schema, data: data)
    end
  end

  def down
  end
end
