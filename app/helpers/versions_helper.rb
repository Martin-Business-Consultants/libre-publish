# frozen_string_literal: true

module VersionsHelper
  def diff_line_marker(op)
    {"add" => "+", "del" => "−"}.fetch(op.to_s, " ")
  end
end
