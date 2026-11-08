module RuneUi
  module Helpers
    module Icons
      # icon(:search); label: makes it an image screen readers announce, else it's hidden.
      def icon(name, css: nil, label: nil)
        paths = RuneUi.icons.fetch(name.to_sym) { raise ArgumentError, "no icon #{name.inspect} (RuneUi.register_icons adds one)" }
        tag.svg(paths.html_safe, class: [ "icon", css ], viewBox: "0 0 16 16",
          aria: (label ? { label: label } : { hidden: true }), role: ("img" if label))
      end
    end
  end
end
