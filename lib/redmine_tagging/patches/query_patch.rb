require_dependency 'issue_query'

module RedmineTagging::Patches::QueryPatch
  def self.prepended(base)
    unless base.available_columns.any? { |column| column.name == :issue_tags }
      base.add_available_column(QueryColumn.new(:issue_tags, caption: :field_tags))
    end
  end

  def initialize_available_filters
    super
    add_available_filter('tags', type: :list_optional, name: l(:field_tags),
                         values: lambda { available_tag_values })
  end

  def available_tag_values
    issues = Issue.visible
    issues = issues.where(project_id: project.id) if project
    tags = ActsAsTaggableOn::Tag.joins(:taggings).
      where(taggings: {taggable_type: 'Issue', taggable_id: issues.select(:id)}).
      distinct.order(:name)
    tags.map { |tag| [tag.name.sub(/\A#/, ''), tag.name.sub(/\A#/, '')] }
  end

  def sql_for_tags_field(field, operator, values)
    taggings = ActsAsTaggableOn::Tagging.where(taggable_type: 'Issue')
    case operator
    when '=', '!'
      names = Array(values).map { |value| '#' + value.to_s.sub(/\A#/, '') }
      tag_ids = ActsAsTaggableOn::Tag.where('LOWER(name) IN (?)', names.map(&:downcase)).select(:id)
      taggings = taggings.where(tag_id: tag_ids)
    when '*', '!*'
      # Any tag / no tags.
    else
      return '1=0'
    end
    membership = ['!', '!*'].include?(operator) ? 'NOT IN' : 'IN'
    "#{Issue.table_name}.id #{membership} (#{taggings.select(:taggable_id).to_sql})"
  end
end

unless IssueQuery.ancestors.include?(RedmineTagging::Patches::QueryPatch)
  IssueQuery.prepend RedmineTagging::Patches::QueryPatch
end
