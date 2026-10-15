require_dependency 'wiki_page'

module RedmineTagging::Patches::WikiPagePatch
  extend ActiveSupport::Concern

  included do
    attr_writer :tags_to_update
    safe_attributes 'tags', if: lambda { |page, user|
      Setting.plugin_redmine_tagging[:wiki_pages_inline] != '1' &&
        user.allowed_to?(:edit_wiki_pages, page.project)
    }

    has_many :wiki_page_tags

    acts_as_taggable

    before_save :update_tags

    searchable_options[:columns] << "#{WikiPageTag.table_name}.tag"
    original_scope = searchable_options[:scope] || self
    searchable_options[:scope] = lambda { |*args|
      scope = original_scope.respond_to?(:call) ? original_scope.call(*args) : original_scope
      scope.includes(:wiki_page_tags)
    }
  end

  # WikiController assigns safe_attributes after finding/creating @page.
  def tags=(value)
    self.tags_to_update = TaggingPlugin::TagsHelper.from_string(value.to_s)
  end

  private

  def update_tags
    if @tags_to_update
      project_context = TaggingPlugin::ContextHelper.context_for(project)
      set_tag_list_on(project_context, @tags_to_update)
    end

    true
  end

end

unless WikiPage.included_modules.include? RedmineTagging::Patches::WikiPagePatch
  WikiPage.send :include, RedmineTagging::Patches::WikiPagePatch
end
