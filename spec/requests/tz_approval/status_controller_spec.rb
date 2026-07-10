# frozen_string_literal: true

RSpec.describe TzApproval::StatusController do
  fab!(:admin) { Fabricate(:admin) }
  fab!(:topic_author) { Fabricate(:user) }
  fab!(:category) { Fabricate(:category) }
  fab!(:second_line_category) { Fabricate(:category) }
  fab!(:topic) { Fabricate(:topic, category: category, user: topic_author) }
  fab!(:tz_group) { Fabricate(:group) }
  fab!(:second_line_group) { Fabricate(:group) }

  let(:token) { "status-token-123" }

  before do
    SiteSetting.tz_approval_status_token = token
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
  end

  def approve_profile(target_topic, prefix, user = admin)
    approved_at = Time.zone.parse("2026-07-04 10:00:00 UTC")

    target_topic.custom_fields["#{prefix}_approved"] = true
    target_topic.custom_fields["#{prefix}_approved_by_id"] = user.id
    target_topic.custom_fields["#{prefix}_approved_at"] = approved_at.iso8601
    target_topic.save_custom_fields(true)
  end

  it "rejects an invalid token" do
    get "/approvals/topic-id/#{topic.id}/wrong-token.json"

    expect(response.status).to eq(403)
    expect(response.parsed_body["ok"]).to eq(false)
    expect(response.parsed_body["error"]).to eq("invalid_token")
  end

  it "rejects requests when the configured token is blank" do
    SiteSetting.tz_approval_status_token = ""

    get "/approvals/topic-id/#{topic.id}/#{token}.json"

    expect(response.status).to eq(403)
  end

  it "returns n8n-compatible approval status by topic id" do
    approve_profile(topic, "tz")

    get "/approvals/topic-id/#{topic.id}/#{token}.json"

    expect(response.status).to eq(200)

    body = response.parsed_body
    expect(body["ok"]).to eq(true)
    expect(body["found"]).to eq(true)
    expect(body["topic_id"]).to eq(topic.id)
    expect(body).not_to have_key("guid")
    expect(body["is_tz"]).to eq(true)
    expect(body["tz_approved"]).to eq(true)
    expect(body["tz_approved_by"]).to include(
      "id" => admin.id,
      "username" => admin.username,
      "at" => "2026-07-04T10:00:00Z",
    )

    tz_approval = body["approvals"].find { |approval| approval["profile_prefix"] == "tz" }
    second_line_approval =
      body["approvals"].find { |approval| approval["profile_prefix"] == "second_line" }

    expect(tz_approval).to include(
      "profile_key" => "tz",
      "profile_label" => "ТЗ",
      "binding_mode" => "category",
      "is_applicable" => true,
      "approved" => true,
      "author_approval_locked" => false,
    )
    expect(second_line_approval).to include(
      "profile_key" => "second_line",
      "is_applicable" => false,
      "approved" => false,
      "author_approval_locked" => false,
    )
    expect(body["ss_approved"]).to eq(false)
    expect(body["ss_approved_by"]).to include("id" => nil, "username" => nil, "at" => nil)
    expect(body["can_set_solution"]).to eq(false)
    expect(body["has_solution"]).to eq(false)
    expect(body["solution"]).to include(
      "post_id" => nil,
      "marked_at" => nil,
      "marked_by" => { "id" => nil, "username" => nil },
      "post_author" => { "id" => nil, "username" => nil },
    )
  end

  it "adds author lock state only inside profile approvals" do
    topic.custom_fields["tz_author_approval_locked"] = true
    topic.save_custom_fields(true)

    get "/approvals/topic-id/#{topic.id}/#{token}.json"

    expect(response.status).to eq(200)
    body = response.parsed_body
    tz_approval = body["approvals"].find { |approval| approval["profile_prefix"] == "tz" }

    expect(tz_approval["author_approval_locked"]).to eq(true)
    expect(body).not_to have_key("author_approval_locked")
    expect(body).to include(
      "is_tz" => true,
      "tz_approved" => false,
      "ss_approved" => false,
      "can_set_solution" => false,
      "has_solution" => false,
    )
  end

  it "keeps ss legacy fields in sync after moving a topic into an ss profile category" do
    source_category = Fabricate(:category)
    ss_category = Fabricate(:category)
    moved_topic = Fabricate(:topic, category: source_category, user: topic_author)

    TzApproval::ProfileRecord.create!(
      key: "ss",
      prefix: "ss",
      label: "СС",
      enabled: true,
      priority: 100,
      binding_mode: "category",
      icon: "file-signature",
      category_ids: [ss_category.id],
    )

    expect(TzApproval.topic_applicable_profile(moved_topic)).to be_nil

    moved_topic.update!(category: ss_category)
    sign_in(admin)

    post "/tz-approval/approve.json", params: { topic_id: moved_topic.id }

    expect(response.status).to eq(200)
    expect(response.parsed_body).to include(
      "approval_profile_key" => "ss",
      "approval_profile_prefix" => "ss",
      "approved" => true,
    )

    get "/approvals/topic-id/#{moved_topic.id}/#{token}.json"

    expect(response.status).to eq(200)

    body = response.parsed_body
    ss_approval = body["approvals"].find { |approval| approval["profile_prefix"] == "ss" }

    expect(ss_approval).to include(
      "profile_key" => "ss",
      "is_applicable" => true,
      "approved" => true,
    )
    expect(ss_approval["approved_by"]).to include(
      "id" => admin.id,
      "username" => admin.username,
      "at" => be_present,
    )
    expect(body["ss_approved"]).to eq(ss_approval["approved"])
    expect(body["ss_approved_by"]).to eq(ss_approval["approved_by"])
    expect(body["tz_approved"]).to eq(false)
  end

  it "falls back to second_line for ss legacy fields" do
    second_line_topic = Fabricate(:topic, category: second_line_category, user: topic_author)
    approve_profile(second_line_topic, "second_line")

    get "/approvals/topic-id/#{second_line_topic.id}/#{token}.json"

    expect(response.status).to eq(200)

    body = response.parsed_body
    second_line_approval =
      body["approvals"].find { |approval| approval["profile_prefix"] == "second_line" }

    expect(second_line_approval).to include(
      "profile_key" => "second_line",
      "is_applicable" => true,
      "approved" => true,
    )
    expect(body["ss_approved"]).to eq(second_line_approval["approved"])
    expect(body["ss_approved_by"]).to eq(second_line_approval["approved_by"])
  end

  it "accepts the status token from a request header" do
    approve_profile(topic, "tz")

    get "/approvals/topic-id/#{topic.id}.json", headers: { "X-TZ-Approval-Token" => token }

    expect(response.status).to eq(200)
    expect(response.parsed_body["ok"]).to eq(true)
    expect(response.parsed_body["topic_id"]).to eq(topic.id)
  end

  it "accepts the status token from a query parameter" do
    approve_profile(topic, "tz")

    get "/approvals/topic-id/#{topic.id}.json", params: { token: token }

    expect(response.status).to eq(200)
    expect(response.parsed_body["ok"]).to eq(true)
    expect(response.parsed_body["topic_id"]).to eq(topic.id)
  end

  it "returns found false for an unknown topic id" do
    get "/approvals/topic-id/999999/#{token}.json"

    expect(response.status).to eq(200)
    expect(response.parsed_body).to include(
      "ok" => true,
      "found" => false,
      "topic_id" => 999999,
      "approvals" => [],
    )
  end
end
