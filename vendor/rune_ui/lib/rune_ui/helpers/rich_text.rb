module RuneUi
  module Helpers
    # Multi-line fields as Lexxy (the app brings the lexxy gem), writing HTML into a plain text
    # column. Plain text saved before opens as paragraphs.
    module RichText
      # toolbar: false hides the formatting buttons (Markdown shortcuts still work), for a
      # message box. mentions: names offered after typing "@", inserted as plain text.
      def rich_text_field(form, method, placeholder: nil, toolbar: true, mentions: nil)
        value = form.object.try(method).to_s
        value = simple_format(value) if value.present? && !value.include?("<")
        tag.div(class: "lexxy") do
          content_tag("lexxy-editor", name: form.field_name(method), id: form.field_id(method), value: value.to_str,
                      placeholder: placeholder, class: "lexxy-content", attachments: "false", toolbar: ("false" unless toolbar)) do
            mention_prompt(mentions)
          end
        end
      end

      def rich_text_field_tag(name, value = nil, id: nil, placeholder: nil, toolbar: true)
        content_tag("lexxy-editor", "", name: name, id: id || name.parameterize, value: value.to_s, placeholder: placeholder,
                    class: "lexxy-content", attachments: "false", toolbar: ("false" unless toolbar))
      end

      def mention_prompt(names)
        return if names.blank?

        content_tag("lexxy-prompt", trigger: "@", name: "mention", "insert-editable-text": "") do
          safe_join(names.map do |name|
            content_tag("lexxy-prompt-item", search: name) do
              safe_join([ tag.template(name, type: "menu"), tag.template("@#{name}", type: "editor") ])
            end
          end)
        end
      end

      # Saved rich text (or plain text) shown, sanitized.
      def rich_text(text)
        return if text.blank?

        html = text.include?("<") ? text : simple_format(text)
        tag.div sanitize(html), class: "lexxy-content"
      end
    end
  end
end
