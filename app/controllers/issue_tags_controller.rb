class IssueTagsController < ApplicationController
  before_action :find_project_by_project_id
  before_action :authorize_tag_management

  def destroy
    tag = ActsAsTaggableOn::Tag.find(params[:id])
    context = TaggingPlugin::ContextHelper.context_for(@project)

    Issue.transaction do
      # Only issue tags belong to this tab; Wiki tags must remain intact.
      issue_ids = tag.taggings.where(context: context, taggable_type: 'Issue').select(:taggable_id)
      @project.issues.where(id: issue_ids).find_each do |issue|
        issue.init_journal(User.current)
        issue.tags_to_update = issue.tag_list_on(context).reject { |name| name == tag.name }
        issue.save!
      end
      tag.destroy! unless tag.taggings.exists?
    end

    flash[:notice] = l(:notice_successful_detached)
    redirect_to controller: 'projects', action: 'settings', tab: 'tags', id: @project
  end

  private

  def authorize_tag_management
    deny_access unless User.current.allowed_to?(:edit_project, @project)
  end
end
