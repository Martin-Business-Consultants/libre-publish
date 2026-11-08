module RuneUi
  module Helpers
    # Small marks: letter avatars, badges, status dots, counts, times, the panel's trail.
    module Marks
      # A coloured initial for anything named, the same colour every time.
      def letter_avatar(name, large: false)
        hue = name.to_s.bytes.sum % 8
        tag.span name.to_s.strip.first.to_s.upcase, class: [ "letter", "letter--#{hue}", ("letter--lg" if large) ], aria: { hidden: true }
      end

      # badge("failed") or badge("pending", "Needs approval"): the status picks the tone through
      # RuneUi.badge_tones. badge("Done 6 Nov", tone: :ok): any text, the tone given. A
      # snake_case status shows humanized; other text as it is.
      def badge(status, label = nil, tone: nil, **options)
        label ||= status.is_a?(Symbol) || status.to_s.match?(/\A[a-z_]+\z/) ? status.to_s.humanize : status.to_s
        extra = options.delete(:class)
        tag.span label, **options, class: [ "badge", "badge--#{tone || RuneUi.tone_for(status)}", extra ]
      end

      # A dot for a state: :attention (amber), :unread (accent), :failed (red), :busy (spinner).
      def status_dot(state, label: nil)
        tag.span class: "status status--#{state}", title: label, aria: { label: label }, role: ("img" if label)
      end

      # A number in a pill (unread, waiting); nothing for zero.
      def count_pill(count)
        tag.span(count, class: "count") if count.to_i.positive?
      end

      # "5 minutes ago" (or "5m ago" with short: true), kept current on the page.
      def time_ago(time, short: false)
        return "—" unless time

        seconds = (Time.current - time).to_i
        text = if !short then "#{time_ago_in_words(time)} ago"
        elsif seconds < 60 then "now"
        elsif seconds < 3600 then "#{seconds / 60}m ago"
        elsif seconds < 86_400 then "#{seconds / 3600}h ago"
        else "#{seconds / 86_400}d ago"
        end
        tag.time text, datetime: time.iso8601, title: time.to_fs(:long),
          data: { controller: "rune-local-time", rune_local_time_datetime_value: time.iso8601, rune_local_time_short_value: short }
      end

      # The trail at the top of the panel: crumbs("Bots", [bot.name, bot]): strings or
      # [label, path]. The last is the current page.
      def crumbs(*parts)
        parts = parts.compact
        content_for :crumbs do
          safe_join(parts.each_with_index.map do |part, index|
            label, path = Array(part)
            node = index == parts.size - 1 ? tag.span(label, class: "crumbs__current") : (path ? link_to(label, path) : tag.span(label))
            index.zero? ? node : safe_join([ tag.span("/", class: "crumbs__sep"), node ])
          end)
        end
      end
    end
  end
end
