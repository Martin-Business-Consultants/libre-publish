# frozen_string_literal: true

json.build @build
# What it reported that waits for approval in Settings › Deploy, if anything.
json.pending_delivery @pending
# As the Go core answers, which @librepublish/astro reads: it warns the build
# when its change of rendering waits for approval.
json.ok true
json.approval_pending @pending.present?
