require_dependency 'queries_helper'

module RedmineTagging::Patches::QueriesHelperPatch
  def column_content(column, item)
    if column.name == :issue_tags
      safe_join(item.issue_tags.map { |tag| link_to_project_tag_filter(@project, tag.tag) }, ', ')
    else
      super
    end
  end
end

unless QueriesHelper.ancestors.include?(RedmineTagging::Patches::QueriesHelperPatch)
  QueriesHelper.prepend RedmineTagging::Patches::QueriesHelperPatch
end
