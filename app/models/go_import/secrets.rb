# frozen_string_literal: true

# The values the Go core sealed with its key, found wherever they are in the
# new database (a column's whole value, or a string in its JSON, as the Go
# core's own import finds them) and opened with the old key
# (GoImport::Keyring), then kept as this core keeps each:
#
# - a token's plaintext (service and personal tokens, for "reveal"):
#   encrypted with this install's Active Record encryption;
# - a webhook's signing secret: as it is (this core keeps it plain);
# - a setting's secret (the GitHub token, a deploy hook): as it is, in the
#   setting's data, where this core's settings screens read it; the email
#   password moves with the rest of Settings › Email to this core's
#   mail_delivery setting, into its encrypted secrets.
#
# One no key opens is cleared, never left looking like a value that works:
# a token still signs in (by its digest) but can't be revealed; a webhook
# gets a new secret (its receiver needs it); a setting loses that value.
class GoImport::Secrets
  ENCRYPTED = {"service_tokens.token" => "ServiceToken", "api_tokens.token" => "ApiToken"}.freeze
  SECURITY = {"starttls" => "starttls", "tls" => "ssl", "ssl" => "ssl", "none" => "none"}.freeze

  def initialize(db, keyring:, report:)
    @db = db
    @keyring = keyring
    @report = report
  end

  def carry
    text_columns.each { |table, column, nullable| carry_column(table, column, nullable) }
    move_email
  end

  private

  # The text columns of the tables copied from the Go database.
  def text_columns
    @db.execute(<<~SQL)
      SELECT m.name, c.name, c."notnull" FROM main.sqlite_master m JOIN pragma_table_info(m.name) c
      WHERE m.type = 'table' AND m.name NOT LIKE 'sqlite_%' AND m.name IN (SELECT name FROM go.sqlite_master WHERE type = 'table')
        AND upper(c.type) NOT LIKE '%BLOB%' AND upper(c.type) NOT LIKE '%INT%'
        AND upper(c.type) NOT IN ('BOOLEAN', 'FLOAT', 'REAL', 'DECIMAL', 'DATETIME', 'DATETIME(6)', 'DATE')
    SQL
  end

  def carry_column(table, column, not_null)
    where = "#{table}.#{column}"
    rows = @db.execute(%(SELECT rowid, CAST("#{column}" AS TEXT) FROM "#{table}" WHERE instr("#{column}", ?) > 0), [GoImport::Keyring::PREFIX])
    rows.each do |rowid, value|
      changed =
        if GoImport::Keyring.sealed?(value)
          whole(where, open(where, value), not_null.to_i == 1)
        elsif value.start_with?("{", "[")
          in_json(where, value)
        else
          value
        end
      @db.execute(%(UPDATE "#{table}" SET "#{column}" = ? WHERE rowid = ?), [changed, rowid]) unless changed == value
    end
  end

  def open(where, value)
    @report.secrets[:total] += 1
    @keyring.open(value).tap do |plain|
      if plain
        @report.secrets[:carried] += 1
      else
        @report.secrets[:cleared][where] += 1
      end
    end
  end

  def whole(where, plain, not_null)
    if (model = ENCRYPTED[where])
      plain && model.constantize.type_for_attribute("token").serialize(plain)
    elsif where == "webhooks.secret"
      plain || Webhook.generate_secret.tap { @report.warn("a webhook's signing secret couldn't be opened, so it has a new one: give its receiver the new secret (Settings › Webhooks)") }
    else
      plain || (not_null ? "" : nil)
    end
  end

  def in_json(where, raw)
    JSON.generate(strings(where, JSON.parse(raw)))
  rescue JSON::ParserError
    raw
  end

  # A value no key opens leaves its object, rather than standing there empty.
  def strings(where, value)
    case value
    when Hash
      value.each_with_object({}) do |(key, item), out|
        opened = strings(where, item)
        out[key] = opened unless opened.nil? && GoImport::Keyring.sealed?(item)
      end
    when Array then value.map { strings(where, it) }
    when String then GoImport::Keyring.sealed?(value) ? open(where, value) : value
    else value
    end
  end

  # Settings › Email (the Go core's "email" setting) as this core's
  # mail_delivery: the server, and the password into its encrypted secrets.
  # Who mail comes from stays in "email", which this core doesn't read.
  def move_email
    raw = @db.get_first_value("SELECT data FROM settings WHERE key = 'email'")
    email = raw ? JSON.parse(raw) : {}
    return if email["smtp_host"].blank? || @db.get_first_value("SELECT 1 FROM settings WHERE key = ?", [MailDelivery::KEY])

    data = {"address" => email["smtp_host"], "port" => email["smtp_port"].presence&.to_i, "security" => SECURITY.fetch(email["smtp_security"].to_s, "starttls"),
            "user_name" => email["smtp_username"].presence, "authentication" => ("plain" if email["smtp_username"].present?)}.compact
    password = email["smtp_password"].presence
    secrets = password && Setting.type_for_attribute("secrets").serialize(JSON.generate("password" => password))
    now = Time.current.utc.strftime("%Y-%m-%d %H:%M:%S.%6N")
    @db.execute("INSERT INTO settings (key, data, secrets, created_at, updated_at) VALUES (?, ?, ?, ?, ?)", [MailDelivery::KEY, JSON.generate(data), secrets, now, now])
    @db.execute("UPDATE settings SET data = ? WHERE key = 'email'", [JSON.generate(email.except("smtp_password"))])
    @report.content[:email_settings_moved] += 1
    if email.values_at("from_name", "from_email", "reply_to").any?(&:present?)
      @report.not_carry("Settings › Email's sender (#{email.values_at("from_name", "from_email").compact_blank.join(" ")}): set who mail comes from here again")
    end
  end
end
