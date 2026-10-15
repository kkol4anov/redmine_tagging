# Run in a separate Ruby process; this intentionally uses minimal Redmine models.
# REDMINE_SOURCE=/path/to/redmine ruby test/standalone/rails52_compatibility.rb
require 'active_record'
require 'sqlite3'
ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
require 'acts-as-taggable-on'
require 'minitest/autorun'
# Isolated database harness: real AR 5.2/tagging engine, minimal Redmine models.
module RedmineTagging; module Patches; end; end
module Redmine; module VERSION; MAJOR = 4; end; end
module Setting
  def self.plugin_redmine_tagging; {wiki_pages_inline: '0'}; end
end
class User
  def self.current; new; end
  def allowed_to?(*); true; end
end
ROOT = File.expand_path('../..', __dir__)
CORE = ENV.fetch('REDMINE_SOURCE')
load "#{CORE}/lib/redmine/safe_attributes.rb"
ActiveRecord::Migration.verbose = false
ActiveRecord::Schema.define do
  create_table(:projects) { |t| t.string :identifier }
  create_table(:issues) { |t| t.integer :project_id; t.string :subject }
  create_table(:wiki_pages) { |t| t.integer :project_id; t.string :title }
end
Dir[File.join(Gem.loaded_specs.fetch('acts-as-taggable-on').full_gem_path, 'db/migrate/*.rb')].sort.each do |f|
  load f
  name = File.basename(f).sub(/^\d+_/, '').sub(/\.rb$/, '').camelize
  name.constantize.migrate(:up)
end
load "#{ROOT}/db/migrate/20161031000001_create_views.rb"
CreateViews.migrate(:up)
class Project < ActiveRecord::Base
  has_many :issues
end
JournalDetail = Struct.new(:attributes) do
  def initialize(attrs); super(attrs); end
end
JournalStub = Struct.new(:details, :saved) do
  def save; self.saved = true; end
end
class Issue < ActiveRecord::Base
  belongs_to :project
  scope :visible, -> { all }
  class_attribute :searchable_options
  self.searchable_options = {columns: []}
  after_save :create_journal
  def init_journal(*); @current_journal ||= JournalStub.new([], false); end
  def create_journal; @current_journal.save if @current_journal; end
  def copy_from(other, options = {}); self.project = other.project; self.subject = other.subject; self; end
end
class WikiPage < ActiveRecord::Base
  include Redmine::SafeAttributes
  belongs_to :project
  class_attribute :searchable_options
  self.searchable_options = {columns: []}
end
# Patches require these Redmine classes, already supplied by this isolated harness.
def require_dependency(*); end
load "#{ROOT}/app/models/issue_tag.rb"
load "#{ROOT}/app/models/wiki_page_tag.rb"
load "#{ROOT}/lib/tagging_plugin/context_helper.rb"
load "#{ROOT}/lib/tagging_plugin/tags_helper.rb"
load "#{ROOT}/lib/redmine_tagging/patches/issue_patch.rb"
load "#{ROOT}/lib/redmine_tagging/patches/wiki_page_patch.rb"
load "#{ROOT}/lib/redmine_tagging/patches/project_patch.rb"
QueryColumn = Struct.new(:name, :options)
class IssueQuery
  def self.available_columns; @columns ||= []; end
  def self.add_available_column(c); available_columns << c; end
  def initialize_available_filters; @available_filters = {'status_id' => {}}; end
  def add_available_filter(name, opts); @available_filters[name] = opts; end
  def l(key); key.to_s; end
  def project; nil; end
  def available_filters; initialize_available_filters unless @available_filters; @available_filters; end
end
load "#{ROOT}/lib/redmine_tagging/patches/query_patch.rb"
load "#{CORE}/lib/redmine/views/api_template_handler.rb"
load "#{ROOT}/lib/tagging_plugin/api_template_handler_patch.rb"

class ApplicationController
  def self.before_action(*); end
  attr_accessor :params
  def flash; @flash ||= {}; end
  def l(key); key; end
  def redirect_to(*); end
  def deny_access; raise 'denied'; end
end
load "#{ROOT}/app/controllers/issue_tags_controller.rb"

class CompatibilityTest < Minitest::Test
  def setup
    ActsAsTaggableOn::Tagging.delete_all
    ActsAsTaggableOn::Tag.delete_all
    Issue.delete_all; WikiPage.delete_all; Project.delete_all
    @project = Project.create!(identifier: 'test-project')
    @issue = Issue.create!(project: @project, subject: 'test')
  end
  def tag(issue, names)
    issue.tags_to_update = names
    issue.save!
  end
  def test_save_clear_and_cyrillic
    tag(@issue, '#метка, #test')
    assert_equal ['#test', '#метка'], @issue.reload.issue_tags.map(&:tag).sort
    tag(@issue, '')
    assert_empty @issue.reload.issue_tags
  end
  def test_journal_and_repeated_init
    tag(@issue, '#one')
    journal = @issue.init_journal(User.current)
    @issue.tags_to_update = '#two'
    @issue.init_journal(User.current)
    @issue.save!
    assert journal.saved
    assert_equal 1, journal.details.size
    assert_equal 'one', journal.details.first.attributes[:old_value]
    assert_equal 'two', journal.details.first.attributes[:value]
  end
  def test_copy
    tag(@issue, '#copy')
    copy = Issue.new.copy_from(@issue)
    copy.save!
    assert_equal ['#copy'], copy.reload.issue_tags.map(&:tag)
  end
  def test_project_move_keeps_tags
    tag(@issue, '#move')
    @issue.tag_list_ctx # Prime source context cache before moving.
    target = Project.create!(identifier: 'target')
    @issue.project = target
    @issue.save!
    assert_equal ['#move'], @issue.reload.issue_tags.map(&:tag)
    assert_equal ['context_target'], @issue.taggings.pluck(:context).uniq
    assert_equal ['#move'], target.tags.pluck(:name)
    assert_empty @project.tags
  end
  def test_wiki_safe_attributes
    page = WikiPage.new(project: @project, title: 'New')
    page.safe_attributes = {'tags' => 'wiki тег'}
    page.save!
    assert_equal ['#wiki', '#тег'], page.wiki_page_tags.map(&:tag).sort
    assert_empty @project.tags # Same numeric issue/wiki IDs must not overlap.
    page.safe_attributes = {'tags' => ''}
    page.save!
    assert_empty page.reload.wiki_page_tags
  end
  def test_query_operators
    tag(@issue, '#one')
    other = Issue.create!(project: @project, subject: 'other')
    q = IssueQuery.new
    assert q.available_filters.key?('status_id')
    assert q.available_filters.key?('tags')
    {'=' => [@issue.id], '!' => [other.id], '*' => [@issue.id], '!*' => [other.id]}.each do |op, ids|
      assert_equal ids, Issue.where(q.sql_for_tags_field('tags', op, ['one'])).pluck(:id)
    end
    assert_empty Issue.where(q.sql_for_tags_field('tags', '=', ["x') OR 1=1 --"])).to_a
    assert_equal [['one', 'one']], q.available_tag_values
  end
  def test_detach_keeps_wiki_and_other_projects
    tag(@issue, '#shared')
    wiki = WikiPage.new(project: @project, title: 'Wiki')
    wiki.tags_to_update = '#shared'
    wiki.save!
    other_project = Project.create!(identifier: 'other')
    other = Issue.create!(project: other_project, subject: 'other')
    tag(other, '#shared')
    controller = IssueTagsController.new
    controller.instance_variable_set(:@project, @project)
    controller.params = {id: ActsAsTaggableOn::Tag.find_by!(name: '#shared').id}
    controller.destroy
    assert_empty @issue.reload.issue_tags
    assert_equal ['#shared'], wiki.reload.wiki_page_tags.map(&:tag)
    assert_equal ['#shared'], other.reload.issue_tags.map(&:tag)
  end

  def test_native_api_templates_preserved
    %w[index show].each do |name|
      path = "#{CORE}/app/views/issues/#{name}.api.rsb"
      template = Struct.new(:identifier, :source).new(path, File.read(path))
      compiled = Redmine::Views::ApiTemplateHandler.call(template)
      assert_equal 1, compiled.scan('api.array :tags').size
      assert_includes compiled, 'visible_custom_field_values'
      assert_includes compiled, 'api.is_private'
      assert_includes compiled, 'journal.visible_details' if name == 'show'
      RubyVM::InstructionSequence.compile(compiled)
      # Removing only the inserted block must reproduce the native compiled template.
      native = Redmine::Views::ApiTemplateHandler.method(:call).super_method.call(template)
      stripped = compiled.sub(/\napi.array :tags do\n.*?\nend\n/m, '')
      assert_equal native, stripped
    end
  end
end
