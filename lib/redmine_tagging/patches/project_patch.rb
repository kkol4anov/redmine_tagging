require_dependency 'project'

module RedmineTagging::Patches::ProjectPatch
  def tags
    ActsAsTaggableOn::Tag.joins(:taggings).
      where(taggings: {taggable_type: 'Issue', taggable_id: issues.select(:id)}).
      distinct.order(:name)
  end
end

unless Project.ancestors.include?(RedmineTagging::Patches::ProjectPatch)
  Project.prepend RedmineTagging::Patches::ProjectPatch
end
