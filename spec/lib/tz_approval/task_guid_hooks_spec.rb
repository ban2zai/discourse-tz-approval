# frozen_string_literal: true

RSpec.describe "task GUID operation hooks" do
  fab!(:user) { Fabricate(:user) }
  fab!(:moderator) { Fabricate(:moderator) }
  fab!(:source_category) { Fabricate(:category) }
  fab!(:target_category) { Fabricate(:category) }

  before do
    TzApproval::ProfileRecord.delete_all
    TzApproval.clear_profiles_cache!
    TzApproval::ProfileRecord.create!(
      key: "second_line",
      prefix: "second_line",
      label: "Вторая линия",
      binding_mode: "category",
      category_ids: [target_category.id],
      require_task_guid: true,
    )
  end

  it "returns the native creation validation error and does not create the topic" do
    TzApproval::TaskGuidRequirement.stubs(:creation_allowed?).returns(false)

    post =
      I18n.with_locale(:ru) do
        PostCreator.create(
          user,
          title: "Тема без связи с внешней задачей",
          raw: "Достаточно длинный текст для создания новой темы.",
          category: target_category.id,
        )
      end

    expect(post).not_to be_persisted
    expect(post.errors[:base]).to include(
      "Отсутствует связь с задачей. Создать тему в этой категории можно только из СЗ.",
    )
  end

  it "keeps skip_validations as a trusted creation bypass" do
    TzApproval::TaskGuidRequirement.expects(:creation_allowed?).never

    post =
      PostCreator.create(
        user,
        title: "Imported topic",
        raw: "Imported topic body",
        category: target_category.id,
        skip_validations: true,
      )

    expect(post).to be_persisted
  end

  it "rejects a PostRevisor category change before the category is modified" do
    topic = Fabricate(:topic, category: source_category)
    post = Fabricate(:post, topic: topic, post_number: 1)
    TzApproval::TaskGuidRequirement.stubs(:category_change_allowed?).returns(false)

    result =
      I18n.with_locale(:ru) do
        PostRevisor.new(post, topic).revise!(
          moderator,
          {
            category_id: target_category.id,
          },
        )
      end

    expect(result).to eq(false)
    expect(post.errors[:base]).to include(
      "Отсутствует связь с задачей. Создать тему в этой категории можно только из СЗ.",
    )
    expect(topic.reload.category_id).to eq(source_category.id)
  end

  it "rejects direct category changes used by per-topic bulk processing" do
    topic = Fabricate(:topic, category: source_category)
    topic.acting_user = moderator
    TzApproval::TaskGuidRequirement.stubs(:category_change_allowed?).returns(false)

    result =
      I18n.with_locale(:ru) { topic.change_category_to_id(target_category.id) }

    expect(result).to eq(false)
    expect(topic.errors[:base]).to include(
      "Отсутствует связь с задачей. Создать тему в этой категории можно только из СЗ.",
    )
    expect(topic.reload.category_id).to eq(source_category.id)
  end

  it "keeps bulk moves per-topic and does not bypass the rule for moderators" do
    topic = Fabricate(:topic, category: source_category)
    Fabricate(:post, topic: topic, post_number: 1)

    changed_ids =
      TopicsBulkAction.new(
        moderator,
        [topic.id],
        {
          type: "change_category",
          category_id: target_category.id,
        },
      ).perform!

    expect(changed_ids).to eq([])
    expect(topic.reload.category_id).to eq(source_category.id)
  end

  it "allows an administrator to bypass the rule during a bulk move" do
    admin = Fabricate(:admin)
    topic = Fabricate(:topic, category: source_category)
    Fabricate(:post, topic: topic, post_number: 1)

    changed_ids =
      TopicsBulkAction.new(
        admin,
        [topic.id],
        {
          type: "change_category",
          category_id: target_category.id,
        },
      ).perform!

    expect(changed_ids).to eq([topic.id])
    expect(topic.reload.category_id).to eq(target_category.id)
  end
end
