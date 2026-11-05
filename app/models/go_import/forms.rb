# frozen_string_literal: true

# The Go Forms plugin's records as the Forms plugin's tables here (forms,
# form_emails, form_submissions): the inverse of the Go core's own import of
# them (its internal/restore/forms.go). The Go plugin keeps them in its
# plugin_kv rows:
#
#   form:<slug>        the form: fields, emails, spam settings, thank-you
#   sub:<slug>:<id>    a submission: values, status, address, browser
#   all:<id>, stat:<slug>   indexes and counts, rebuilt here from the rows
#
# Each form keeps its slug, name, fields (as the Go builder wrote them, which
# the Rails plugin reads by the same names), submit label and thank-you;
# "active" is published, anything else a draft. The email to the site's
# people is its "notification" and the one to the visitor its
# "confirmation", merge tags written the Rails plugin's way. Submissions keep
# their answers, address, browser, page and status.
#
# Only when this install has the Forms plugin's tables: without them, and
# for every other plugin's records, what the Go plugins kept is returned for
# the import to write to a file beside the database, and reported.
class GoImport::Forms
  TAGS = {"form_name" => "form_title", "date" => "submitted_at"}.freeze

  def initialize(db, report:, tables:)
    @db = db
    @report = report
    @tables = tables
  end

  # The records no table here takes, by plugin.
  def convert
    records = @db.execute("SELECT plugin_key, key, value FROM go.plugin_kv ORDER BY plugin_key, key").group_by(&:first)
    forms = records.delete("forms")
    if forms && @tables.include?("forms") && @tables.include?("form_submissions")
      carry(forms.to_h { |_, key, value| [key, parse(value)] })
    elsif forms
      records["forms"] = forms
      @report.warn("this install has no Forms plugin tables: the Go site's forms and submissions are kept in a file beside the database, not carried")
    end
    records.each_key { |plugin| @report.not_carry("the Go #{plugin} plugin's #{records[plugin].size} record(s) (kept in a file beside the database)") }
    records.transform_values { |rows| rows.to_h { |_, key, value| [key, parse(value)] } }
  rescue SQLite3::SQLException
    {}
  end

  private

  def parse(value)
    text = value.to_s.dup.force_encoding(Encoding::UTF_8)
    JSON.parse(text)
  rescue JSON::ParserError
    text
  end

  def carry(records)
    taken = @db.execute("SELECT slug FROM forms").flatten
    ids = {}
    records.each do |key, form|
      next unless key.start_with?("form:") && form.is_a?(Hash)

      slug = form["slug"].presence || key.delete_prefix("form:")
      if taken.include?(slug)
        @report.not_carry("form #{slug}: this install's forms already have one by that slug (from the Rails core's tables the Go site still kept)")
        next
      end
      ids[slug] = insert_form(slug, form)
    end
    records.each do |key, submission|
      next unless key.start_with?("sub:") && submission.is_a?(Hash)

      form_id = ids[submission["form"].presence || key.split(":")[1]]
      insert_submission(form_id, submission) if form_id
    end
  end

  def insert_form(slug, form)
    @report.forms[:forms] += 1
    values = [slug, form["name"].presence || slug, (form["status"] == "active") ? "published" : "draft", JSON.generate(fields(form)),
      form["submit_label"].presence || "Submit", form["success_message"], time(form["created_at"]), time(form["updated_at"])]
    @db.execute("INSERT INTO forms (slug, title, status, fields, submit_label, success_message, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)", values)
    id = @db.last_insert_row_id
    emails(id, form)
    not_carried(slug, form)
    id
  end

  def fields(form)
    Array(form["fields"]).filter_map { it.except("id") if it.is_a?(Hash) }
  end

  def emails(id, form)
    return unless @tables.include?("form_emails")

    [["notification", form["admin_enabled"], Array(form["admin_to"]).join(", "), nil, form["admin_subject"], form["admin_message"]],
      ["confirmation", form["client_enabled"], nil, form["client_to_field"].presence, form["client_subject"], form["client_message"]]].each do |kind, enabled, recipients, from_field, subject, body|
      next if subject.blank? && body.blank? && recipients.blank?

      now = time(form["updated_at"])
      @db.execute("INSERT INTO form_emails (form_id, kind, enabled, recipients, from_field, subject, body, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        [id, kind, enabled ? 1 : 0, recipients.presence, from_field, tags(subject.to_s), tags(body.to_s), now, now])
      @report.forms[:emails] += 1
    end
  end

  def insert_submission(form_id, submission)
    at = time(submission["submitted_at"])
    meta = {"status" => submission["status"], "user_agent" => submission["user_agent"], "referer" => submission["referer"],
            "spam_reason" => submission["spam_reason"], "go_id" => submission["id"]}.compact_blank
    @db.execute("INSERT INTO form_submissions (form_id, data, ip, meta, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
      [form_id, JSON.generate(submission["values"] || {}), submission["ip"].presence, JSON.generate(meta), at, at])
    @report.forms[:submissions] += 1
  end

  # {{ form_name }} as {{form_title}}; a field's {{ name }} as {{name}}.
  def tags(text)
    text.gsub(/\{\{\s*([^{}]+?)\s*\}\}/) { "{{#{TAGS.fetch($1, $1)}}}" }
  end

  def not_carried(slug, form)
    @report.not_carry("form #{slug}: its thank-you page (#{form["redirect_url"]})") if form["redirect_url"].present?
    @report.not_carry("form #{slug}: its captcha (#{form["captcha"]}) and spam settings") if form["captcha"].present? && form["captcha"] != "none"
    @report.not_carry("form #{slug}: its hook (#{form["hook_url"]})") if form["hook_url"].present?
    @report.not_carry("form #{slug}: its cc and bcc") if Array(form["admin_cc"]).any? || Array(form["admin_bcc"]).any?
    @report.not_carry("form #{slug}: \"keep submissions\" was off there") if form["store_submissions"] == false
  end

  def time(value)
    (Time.zone.parse(value.to_s) || Time.current).utc.strftime("%Y-%m-%d %H:%M:%S.%6N")
  rescue ArgumentError
    Time.current.utc.strftime("%Y-%m-%d %H:%M:%S.%6N")
  end
end
