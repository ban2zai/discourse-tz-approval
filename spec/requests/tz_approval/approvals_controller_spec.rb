# frozen_string_literal: true

RSpec.describe TzApproval::ApprovalsController do
  fab!(:admin) { Fabricate(:admin) }
  fab!(:other_admin) { Fabricate(:admin) }
  fab!(:user) { Fabricate(:user) }
  fab!(:second_line_user) { Fabricate(:user) }
  fab!(:topic_author) { Fabricate(:user) }
  fab!(:category) { Fabricate(:category) }
  fab!(:second_line_category) { Fabricate(:category) }
  fab!(:topic) { Fabricate(:topic, category: category, user: topic_author) }
  fab!(:second_line_topic) do
    Fabricate(:topic, category: second_line_category, user: topic_author)
  end
  fab!(:tz_group) { Fabricate(:group) }
  fab!(:second_line_group) { Fabricate(:group) }

  before do
    SiteSetting.tz_approval_binding_mode = "category"
    SiteSetting.tz_approval_categories = category.id.to_s
    SiteSetting.tz_approval_allowed_groups = tz_group.id.to_s

    TzApproval::ProfileRecord.delete_all
    TzApproval.clear_profiles_cache!
    TzApproval.ensure_default_profile!
    TzApproval::ProfileRecord.create!(
      key: "second_line",
      prefix: "second_line",
      label: "Вторая линия",
      enabled: true,
      priority: 200,
      binding_mode: "category",
      icon: "clipboard-check",
      category_ids: [second_line_category.id],
      allowed_group_ids: [second_line_group.id],
      approve_text: "Одобрить вторую линию",
      unapprove_text: "Снять одобрение второй линии",
      approved_text: "Вторая линия одобрена",
      unapproved_text: "Одобрение второй линии снято",
      approved_by_author_text: "Вторая линия одобрена — Автор темы",
      approved_action_text: "%{username} одобрил вторую линию",
      unapproved_action_text: "%{username} снял одобрение второй линии",
      approved_description: "Вторая линия подтверждена",
      unapproved_description: "Одобрение второй линии снято",
    )

    GroupUser.create!(group: tz_group, user: user)
    GroupUser.create!(group: second_line_group, user: second_line_user)

    sign_in(admin)
  end

  def approve_topic(target_topic = topic)
    post "/tz-approval/approve.json", params: { topic_id: target_topic.id }
  end

  def unapprove_topic(target_topic = topic)
    post "/tz-approval/unapprove.json", params: { topic_id: target_topic.id }
  end

  def lock_author_approval(target_topic = topic)
    post "/tz-approval/lock-author-approval.json", params: { topic_id: target_topic.id }
  end

  def unlock_author_approval(target_topic = topic)
    post "/tz-approval/unlock-author-approval.json", params: { topic_id: target_topic.id }
  end

  def approval_posts(target_topic = topic, action_code = "tz_approved")
    small_action_posts(target_topic, action_code)
  end

  def unapproval_posts(target_topic = topic, action_code = "tz_unapproved")
    small_action_posts(target_topic, action_code)
  end

  def author_lock_posts(target_topic = topic, action_code = "tz_author_locked")
    small_action_posts(target_topic, action_code)
  end

  def author_unlock_posts(target_topic = topic, action_code = "tz_author_unlocked")
    small_action_posts(target_topic, action_code)
  end

  def small_action_posts(target_topic, action_code)
    Post.where(
      topic_id: target_topic.id,
      post_type: Post.types[:small_action],
      action_code: action_code,
    )
  end

  def topic_user(target_user = admin, target_topic = topic)
    TopicUser.find_by(user_id: target_user.id, topic_id: target_topic.id)
  end

  def latest_notification
    Notification.order(:id).last
  end

  it "approves the TZ topic and keeps the legacy custom fields and payload" do
    approve_topic

    expect(response.status).to eq(200)

    topic.reload
    expect(topic.custom_fields["tz_approved"]).to eq(true)
    expect(topic.custom_fields["tz_approved_by_id"]).to eq(admin.id)
    expect(topic.custom_fields["tz_approved_at"]).to be_present
    expect(response.parsed_body["approval_profile_key"]).to eq("tz")
    expect(response.parsed_body["approval_profile_prefix"]).to eq("tz")
    expect(response.parsed_body["approved"]).to eq(true)
    expect(response.parsed_body["tz_approved"]).to eq(true)

    approval_post = approval_posts.first
    expect(approval_posts.count).to eq(1)
    expect(topic.custom_fields["tz_approval_post_id"].to_i).to eq(approval_post.id)
    expect(approval_post.raw).to include("одобрил это ТЗ")
  end

  it "approves a dynamic profile topic with prefixed custom fields only" do
    approve_topic(second_line_topic)

    expect(response.status).to eq(200)

    second_line_topic.reload
    expect(second_line_topic.custom_fields["second_line_approved"]).to eq(true)
    expect(second_line_topic.custom_fields["second_line_approved_by_id"]).to eq(admin.id)
    expect(second_line_topic.custom_fields["second_line_approved_at"]).to be_present
    expect(second_line_topic.custom_fields["tz_approved"]).to be_nil
    expect(response.parsed_body["approval_profile_key"]).to eq("second_line")
    expect(response.parsed_body["approval_profile_prefix"]).to eq("second_line")
    expect(response.parsed_body["approval_approved_text"]).to eq("Вторая линия одобрена")
    expect(response.parsed_body["tz_approved"]).to eq(false)

    approval_post = approval_posts(second_line_topic, "second_line_approved").first
    expect(second_line_topic.custom_fields["second_line_approval_post_id"].to_i).to eq(
      approval_post.id,
    )
    expect(approval_post.raw).to include("одобрил вторую линию")
  end

  it "uses separate allowed groups for each approval profile" do
    sign_in(user)
    approve_topic
    expect(response.status).to eq(200)

    approve_topic(second_line_topic)
    expect(response.status).to eq(403)

    sign_in(second_line_user)
    approve_topic(second_line_topic)
    expect(response.status).to eq(200)
  end

  it "delays approval for topic authors even when they are in an approval group" do
    SiteSetting.tz_author_approval_delay = 1.hour.to_i
    GroupUser.create!(group: tz_group, user: topic_author)
    sign_in(topic_author)

    approve_topic
    expect(response.status).to eq(403)

    topic.update!(created_at: 2.hours.ago)

    approve_topic
    expect(response.status).to eq(200)
  end

  it "uses priority when profile categories overlap" do
    second_line_profile = TzApproval::ProfileRecord.find_by!(key: "second_line")
    second_line_profile.update!(category_ids: [category.id], priority: 50)

    approve_topic

    expect(response.status).to eq(200)
    expect(response.parsed_body["approval_profile_key"]).to eq("second_line")
    topic.reload
    expect(topic.custom_fields["second_line_approved"]).to eq(true)
    expect(topic.custom_fields["tz_approved"]).to be_nil
  end

  it "does not create another approval post when the topic is already approved" do
    approve_topic
    expect(response.status).to eq(200)
    expect(approval_posts.count).to eq(1)

    Guardian.any_instance.stubs(:ensure_can_approve_tz!)

    approve_topic

    expect(response.status).to eq(200)
    expect(response.parsed_body["tz_approved"]).to eq(true)
    expect(response.parsed_body["approved"]).to eq(true)
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
    expect(response.parsed_body["approved"]).to eq(false)
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

  it "stores profile data in author notifications" do
    sign_in(second_line_user)

    approve_topic(second_line_topic)

    expect(response.status).to eq(200)
    expect(latest_notification.notification_type).to eq(Notification.types[:tz_approval])

    data = JSON.parse(latest_notification.data)
    expect(data["profile_key"]).to eq("second_line")
    expect(data["profile_prefix"]).to eq("second_line")
    expect(data["profile_label"]).to eq("Вторая линия")
  end

  describe "author approval lock" do
    it "rejects anonymous users and users outside the approval group" do
      sign_out
      lock_author_approval
      expect(response.status).to eq(403)

      sign_in(Fabricate(:user))
      lock_author_approval
      expect(response.status).to eq(403)
    end

    it "never lets the topic author manage their own lock" do
      sign_in(topic_author)
      lock_author_approval
      expect(response.status).to eq(403)

      GroupUser.create!(group: tz_group, user: topic_author)
      lock_author_approval
      expect(response.status).to eq(403)

      admin_topic = Fabricate(:topic, category: category, user: admin)
      sign_in(admin)
      lock_author_approval(admin_topic)
      expect(response.status).to eq(403)

      unlock_author_approval(admin_topic)
      expect(response.status).to eq(403)
    end

    it "locks author approval and creates one status post and notification" do
      sign_in(user)

      lock_author_approval

      expect(response.status).to eq(200)
      expect(response.parsed_body).to include(
        "author_approval_locked" => true,
        "author_approval_locked_by_id" => user.id,
        "author_approval_locked_by_username" => user.username,
        "can_lock_author_approval" => false,
        "can_unlock_author_approval" => true,
      )

      topic.reload
      expect(topic.custom_fields["tz_author_approval_locked"]).to eq(true)
      expect(topic.custom_fields["tz_author_approval_locked_by_id"]).to eq(user.id)
      expect(topic.custom_fields["tz_author_approval_locked_at"]).to be_present

      lock_post = author_lock_posts.first
      expect(author_lock_posts.count).to eq(1)
      expect(topic.custom_fields["tz_author_approval_lock_post_id"].to_i).to eq(lock_post.id)
      expect(lock_post.raw).to include("запретил автору самостоятельно одобрять")

      expect(latest_notification.notification_type).to eq(Notification.types[:tz_approval])
      notification_data = JSON.parse(latest_notification.data)
      expect(notification_data["action"]).to eq("author_locked")
      expect(notification_data["description"]).to eq(
        "Автору запрещено самостоятельно одобрять ТЗ",
      )
    end

    it "uses the active profile prefix for lock fields and posts" do
      sign_in(second_line_user)

      lock_author_approval(second_line_topic)

      expect(response.status).to eq(200)
      second_line_topic.reload
      expect(second_line_topic.custom_fields["second_line_author_approval_locked"]).to eq(true)
      expect(second_line_topic.custom_fields["tz_author_approval_locked"]).to be_nil
      expect(author_lock_posts(second_line_topic, "second_line_author_locked").count).to eq(1)
    end

    it "keeps repeated lock requests idempotent for authorized users" do
      sign_in(user)

      2.times do
        lock_author_approval
        expect(response.status).to eq(200)
      end

      expect(author_lock_posts.count).to eq(1)
      expect(
        Notification.where(
          user_id: topic_author.id,
          notification_type: Notification.types[:tz_approval],
        ).count,
      ).to eq(1)
    end

    it "unlocks as staff, clears fields, and preserves the historical lock post" do
      sign_in(user)
      lock_author_approval
      expect(response.status).to eq(200)
      lock_post = author_lock_posts.first

      sign_in(admin)
      unlock_author_approval

      expect(response.status).to eq(200)
      expect(response.parsed_body).to include(
        "author_approval_locked" => false,
        "can_lock_author_approval" => true,
        "can_unlock_author_approval" => false,
      )

      topic.reload
      expect(topic.custom_fields["tz_author_approval_locked"]).to be_nil
      expect(topic.custom_fields["tz_author_approval_locked_by_id"]).to be_nil
      expect(topic.custom_fields["tz_author_approval_locked_at"]).to be_nil
      expect(topic.custom_fields["tz_author_approval_lock_post_id"]).to be_nil
      expect(lock_post.reload.deleted_at).to be_nil
      expect(author_unlock_posts.count).to eq(1)

      notification_data = JSON.parse(latest_notification.data)
      expect(notification_data["action"]).to eq("author_unlocked")
      expect(notification_data["description"]).to eq(
        "Автору снова разрешено самостоятельно одобрять ТЗ",
      )
    end

    it "keeps repeated unlock requests idempotent but rejects outsiders" do
      unlock_author_approval
      expect(response.status).to eq(200)
      expect(author_unlock_posts.count).to eq(0)

      sign_in(Fabricate(:user))
      unlock_author_approval
      expect(response.status).to eq(403)
      expect(author_unlock_posts.count).to eq(0)
    end

    it "blocks all author approval interactions until another approver unlocks the topic" do
      SiteSetting.tz_author_approval_delay = 0
      sign_in(user)
      lock_author_approval
      expect(response.status).to eq(200)

      GroupUser.create!(group: tz_group, user: topic_author)
      sign_in(topic_author)
      approve_topic
      expect(response.status).to eq(403)

      sign_in(user)
      unlock_author_approval
      expect(response.status).to eq(200)

      sign_in(topic_author)
      approve_topic
      expect(response.status).to eq(200)

      sign_in(user)
      lock_author_approval
      expect(response.status).to eq(200)

      sign_in(topic_author)
      unapprove_topic
      expect(response.status).to eq(403)
      topic.reload
      expect(topic.custom_fields["tz_approved"]).to eq(true)

      sign_in(user)
      unlock_author_approval
      expect(response.status).to eq(200)

      sign_in(topic_author)
      unapprove_topic
      expect(response.status).to eq(200)
    end

    it "blocks a staff author from approving while the lock is active" do
      admin_topic = Fabricate(:topic, category: category, user: admin)
      sign_in(other_admin)
      lock_author_approval(admin_topic)
      expect(response.status).to eq(200)

      sign_in(admin)
      approve_topic(admin_topic)
      expect(response.status).to eq(403)
    end

    it "blocks a staff author from removing their own approval while the lock is active" do
      admin_topic = Fabricate(:topic, category: category, user: admin)
      sign_in(admin)
      approve_topic(admin_topic)
      expect(response.status).to eq(200)

      sign_in(other_admin)
      lock_author_approval(admin_topic)
      expect(response.status).to eq(200)

      sign_in(admin)
      unapprove_topic(admin_topic)
      expect(response.status).to eq(403)
      admin_topic.reload
      expect(admin_topic.custom_fields["tz_approved"]).to eq(true)
    end

    it "lets an approver approve and unapprove while preserving the lock" do
      sign_in(user)
      lock_author_approval
      expect(response.status).to eq(200)

      approve_topic
      expect(response.status).to eq(200)
      topic.reload
      expect(topic.custom_fields["tz_author_approval_locked"]).to eq(true)

      unapprove_topic
      expect(response.status).to eq(200)
      topic.reload
      expect(topic.custom_fields["tz_author_approval_locked"]).to eq(true)
    end

    it "allows locking an already approved topic" do
      approve_topic
      expect(response.status).to eq(200)

      sign_in(user)
      lock_author_approval

      expect(response.status).to eq(200)
      topic.reload
      expect(topic.custom_fields["tz_approved"]).to eq(true)
      expect(topic.custom_fields["tz_author_approval_locked"]).to eq(true)
    end
  end
end
