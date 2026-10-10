# frozen_string_literal: true

module Cms
  # What a production install is configured with (docs/install.md), checked
  # as it boots: a missing secret or a value the app would misread stops the
  # boot with every problem named, rather than surfacing later as a 500, a
  # login that never sticks or mail that never sends. What an install can
  # run without (outbound mail, an APP_HOST) is a warning in the log.
  #
  #   errors, warnings = Cms::EnvCheck.new(ENV).call
  class EnvCheck
    class Invalid < StandardError; end

    BOOLEANS = %w[ASSUME_SSL CMS_FORCE_SSL CMS_UPDATE_CHECK SMTP_INSECURE_TLS SOLID_QUEUE_IN_PUMA].freeze
    INTEGERS = %w[SMTP_PORT RAILS_MAX_THREADS WEB_CONCURRENCY JOB_CONCURRENCY PORT CMS_BACKUP_KEEP].freeze
    ENCRYPTION = %w[AR_ENCRYPTION_PRIMARY_KEY AR_ENCRYPTION_DETERMINISTIC_KEY AR_ENCRYPTION_KEY_DERIVATION_SALT].freeze
    # The core's update strategies; installed plugins add theirs (Upgrade).
    UPDATES = %w[local github in_place manual].freeze

    def initialize(env, secret_key_base: nil)
      @env = env
      @secret_key_base = secret_key_base
    end

    # [errors, warnings], each a list of sentences.
    def call
      @errors = []
      @warnings = []
      secrets
      host
      formats
      groups
      [@errors, @warnings]
    end

    # Raises Invalid naming every error; returns the warnings.
    def call!
      errors, warnings = call
      raise Invalid, "This install's configuration can't be used:\n#{errors.map { "  - #{it}" }.join("\n")}" if errors.any?

      warnings
    end

    private

    def value(name) = @env[name].to_s.strip.presence

    def secrets
      key = value("SECRET_KEY_BASE") || @secret_key_base
      if key.blank?
        @errors << "SECRET_KEY_BASE is missing: sessions, signed cookies and (without AR_ENCRYPTION_*) every encrypted value depend on it."
      elsif key.length < 64
        @warnings << "SECRET_KEY_BASE is #{key.length} characters; a new one should be at least 64 (`bin/rails secret`)."
      end

      set = ENCRYPTION.select { value(it) }
      return if set.empty? || set.size == ENCRYPTION.size

      @warnings << "Only #{set.join(", ")} of the AR_ENCRYPTION_* keys are set; the rest derive from SECRET_KEY_BASE. Set all three, or none."
    end

    def host
      host = value("APP_HOST")
      if host.nil?
        @warnings << "APP_HOST isn't set, so links in email, asset URLs and form actions say https://localhost. Set it to the address people use."
      elsif host.match?(%r{[/:@\s]}) && !host.match?(/\A[^\/:@\s]+:\d+\z/)
        @errors << "APP_HOST is #{host.inspect}: give the host (and port, if any) alone, like cms.example.com — no scheme or path."
      end

      protocol = value("APP_PROTOCOL")
      @errors << "APP_PROTOCOL is #{protocol.inspect}: it's https or http." if protocol && !%w[https http].include?(protocol)
    end

    def formats
      BOOLEANS.each do |name|
        next unless (v = value(name))

        @errors << "#{name} is #{v.inspect}: it's true or false." unless %w[true false].include?(v)
      end
      INTEGERS.each do |name|
        next unless (v = value(name))

        @errors << "#{name} is #{v.inspect}: it's a whole number." unless v.match?(/\A\d+\z/)
      end
      updates_allowed = UPDATES + Cms::Plugins.update_strategy_names
      if (updates = value("CMS_UPDATES")) && !updates_allowed.include?(updates)
        @errors << "CMS_UPDATES is #{updates.inspect}: it's one of #{updates_allowed.join(", ")}."
      end
      if (from = value("MAIL_FROM_ADDRESS")) && !from.match?(/\A[^@\s]+@[^@\s]+\z/)
        @errors << "MAIL_FROM_ADDRESS is #{from.inspect}: it's an email address."
      end
    end

    def groups
      @warnings << "SMTP_PASSWORD isn't set, so the install can't send mail (password resets, invitations, form notifications)." unless value("SMTP_PASSWORD")
    end
  end
end
