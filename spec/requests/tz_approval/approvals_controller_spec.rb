# frozen_string_literal: true

RSpec.describe TzApproval::ApprovalsController do
  fab!(:admin) { Fabricate(:admin) }
  fab!(:other_admin) { Fabricate(:admin) }
  fab!(:category) { Fabricate(:category) }
  fab!(:topic) { Fabricate(:topic, category: category) }

  before do
    SiteSetting.tz_approval_binding_mode = "category"
    SiteSetting.tz_approval_categories = category.id.to_s
    sign_in(admin)
  end

  def approve_topic
    post "/tz-approval/approve.json", params: { topic_id: topic.id }
  end

  def unapprove_topic
    post "/tz-approval/unapprove.json", params: { topic_id: topic.id }
  end

  def approval_posts
    small_action_posts("tz_approved")
  end

  def unapproval_posts
    small_action_posts("tz_unapproved")
  end

  def small_action_posts(action_code)
    Post.where(
      topic_id:    topic.id,
      post_type:   Post.types[:small_action],
      action_code: action_code,
    )
  end

  def topic_user(user = admin)
    TopicUser.find_by(user_id: user.id, topic_id: topic.id)
  end

  it "approves the topic and stores the approval status post id" do
    approve_topic

    expect(response.status).to eq(200)

    topic.reload
    expect(topic.custom_fields["tz_approved"]).to eq(true)
    expect(topic.custom_fields["tz_approved_by_id"]).to eq(admin.id)
    expect(topic.custom_fields["tz_approved_at"]).to be_present

    approval_post = approval_posts.first
    expect(approval_posts.count).to eq(1)
    expect(topic.custom_fields["tz_approval_post_id"].to_i).to eq(approval_post.id)
  end

  it "does not create another approval post when the topic is already approved" do
    approve_topic
    expect(response.status).to eq(200)
    expect(approval_posts.count).to eq(1)

    Guardian.any_instance.stubs(:ensure_can_approve_tz!)

    approve_topic

    expect(response.status).to eq(200)
    expect(response.parsed_body["tz_approved"]).to eq(true)
    expect(approval_posts.count).to eq(1)
  end

  it "sets a no-op approving user to watching when the topic was already approved" do
    approve_topic
    expect(response.status).to eq(200)

    sign_in(other_admin)
    Guardian.any_instance.stubs(:ensure_can_approve_tz!)

    approve_topic

    expect(response.status).to eq(200)
    expect(response.parsed_body["tz_approved"]).to eq(true)
    expect(approval_posts.count).to eq(1)
    expect(topic_user(other_admin).notification_level).to eq(TopicUser.notification_levels[:watching])
  end

  it "sets the approving user to watching the topic" do
    TopicUser.change(
      admin,
      topic.id,
      notification_level: TopicUser.notification_levels[:regular],
    )

    approve_topic

    expect(response.status).to eq(200)
    expect(topic_user.notification_level).to eq(TopicUser.notification_levels[:watching])
  end

  it "keeps approval history posts when approval is removed" do
    approve_topic
    expect(response.status).to eq(200)

    approval_post = approval_posts.first

    unapprove_topic

    expect(response.status).to eq(200)
    expect(approval_post.reload.deleted_at).to be_nil
    expect(approval_posts.count).to eq(1)
    expect(unapproval_posts.count).to eq(1)

    topic.reload
    expect(topic.custom_fields["tz_approved"]).to be_nil
    expect(topic.custom_fields["tz_approved_by_id"]).to be_nil
    expect(topic.custom_fields["tz_approved_at"]).to be_nil
    expect(topic.custom_fields["tz_approval_post_id"]).to be_nil
  end

  it "does not change notification level when approval is removed" do
    approve_topic
    expect(response.status).to eq(200)

    TopicUser.change(
      admin,
      topic.id,
      notification_level: TopicUser.notification_levels[:regular],
    )

    unapprove_topic

    expect(response.status).to eq(200)
    expect(topic_user.notification_level).to eq(TopicUser.notification_levels[:regular])
  end
end
