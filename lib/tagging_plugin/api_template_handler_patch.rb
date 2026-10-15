require_dependency 'redmine/views/api_template_handler'

module TaggingPlugin
  # Extend the native template instead of replacing it with a Redmine 3 copy.
  # This preserves visible custom fields, journals and all core API attributes.
  module ApiTemplateHandlerPatch
    def call(template)
      compiled = super
      return compiled unless template.identifier.to_s.tr('\\', '/').match?(%r{/issues/(index|show)\.api\.rsb\z})

      compiled.sub(/^(\s*)api\.closed_on\s+(@?issue)\.closed_on[^\S\n]*$/) do |line|
        issue_variable = Regexp.last_match(2)
        line + "\napi.array :tags do\n" +
          "  #{issue_variable}.issue_tags.each do |issue_tag|\n" +
          "    api.tag(:id => issue_tag.title)\n" +
          "  end\nend\n"
      end
    end
  end
end

handler = Redmine::Views::ApiTemplateHandler.singleton_class
unless handler.ancestors.include?(TaggingPlugin::ApiTemplateHandlerPatch)
  handler.prepend TaggingPlugin::ApiTemplateHandlerPatch
end
