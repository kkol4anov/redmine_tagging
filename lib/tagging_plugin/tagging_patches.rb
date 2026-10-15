require_dependency 'projects_helper'

module TaggingPlugin
  module ProjectsHelperPatch
    def project_settings_tabs
      tabs = super
      if User.current.allowed_to?(:edit_project, @project)
        tabs << { name: 'tags', partial: 'tagging/tagtab', label: :tagging_tab_label }
      end
      tabs
    end
  end
end

unless ProjectsHelper.ancestors.include?(TaggingPlugin::ProjectsHelperPatch)
  ProjectsHelper.prepend TaggingPlugin::ProjectsHelperPatch
end
