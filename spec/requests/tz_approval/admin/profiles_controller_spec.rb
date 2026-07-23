# frozen_string_literal: true

RSpec.describe TzApproval::Admin::ProfilesController do
  fab!(:admin) { Fabricate(:admin) }
  fab!(:user) { Fabricate(:user) }
  fab!(:category) { Fabricate(:category) }
  fab!(:group) { Fabricate(:group) }

  before do
    TzApproval::ProfileRecord.delete_all
    TzApproval.clear_profiles_cache!
  end

  def valid_profile_params
    {
      key: "second_line",
      prefix: "second_line",
      label: "Вторая линия",
      enabled: true,
      priority: 200,
      binding_mode: "category",
      require_task_guid: true,
      icon: "clipboard-check",
      category_ids: [category.id],
      allowed_group_ids: [group.id],
      tags: [],
      approve_text: "Одобрить вторую линию",
      unapprove_text: "Снять одобрение второй линии",
      approved_text: "Вторая линия одобрена",
      unapproved_text: "Одобрение второй линии снято",
      approved_by_author_text: "Вторая линия одобрена — Автор темы",
      approved_action_text: "%{username} одобрил вторую линию",
      unapproved_action_text: "%{username} снял одобрение второй линии",
      author_locked_action_text: "%{username} запретил самоодобрение второй линии",
      author_unlocked_action_text: "%{username} разрешил самоодобрение второй линии",
      approved_description: "Вторая линия подтверждена",
      unapproved_description: "Одобрение второй линии снято",
    }
  end

  it "requires admin access" do
    sign_in(user)

    get "/admin/plugins/tz-approval/profiles.json"

    expect(response.status).to eq(403)
  end

  it "lists profiles and seeds the default TZ profile" do
    sign_in(admin)

    get "/admin/plugins/tz-approval/profiles.json"

    expect(response.status).to eq(200)
    expect(response.parsed_body["profiles"].map { |profile| profile["key"] }).to include("tz")
    expect(response.parsed_body["categories"]).to be_present
    expect(response.parsed_body["groups"]).to be_present
  end

  it "creates, updates, and deletes a profile" do
    sign_in(admin)

    post "/admin/plugins/tz-approval/profiles.json", params: { profile: valid_profile_params }
    expect(response.status).to eq(200)
    expect(response.parsed_body["profile"]).to include(
      "require_task_guid" => true,
      "author_locked_action_text" => "%{username} запретил самоодобрение второй линии",
      "author_unlocked_action_text" => "%{username} разрешил самоодобрение второй линии",
    )

    profile_id = response.parsed_body["profile"]["id"]

    put "/admin/plugins/tz-approval/profiles/#{profile_id}.json",
        params: {
          profile: valid_profile_params.merge(label: "Вторая линия форума", prefix: "ignored"),
        }

    expect(response.status).to eq(200)
    expect(response.parsed_body["profile"]["label"]).to eq("Вторая линия форума")
    expect(response.parsed_body["profile"]["prefix"]).to eq("second_line")
    expect(response.parsed_body["profile"]["author_locked_action_text"]).to eq(
      "%{username} запретил самоодобрение второй линии",
    )
    expect(response.parsed_body["profile"]["require_task_guid"]).to eq(true)

    delete "/admin/plugins/tz-approval/profiles/#{profile_id}.json"

    expect(response.status).to eq(200)
    expect(TzApproval::ProfileRecord.exists?(profile_id)).to eq(false)
  end

  it "forces the task GUID requirement off for tag profiles" do
    sign_in(admin)

    post "/admin/plugins/tz-approval/profiles.json", params: { profile: valid_profile_params }
    profile_id = response.parsed_body["profile"]["id"]

    put "/admin/plugins/tz-approval/profiles/#{profile_id}.json",
        params: {
          profile: valid_profile_params.merge(binding_mode: "tag", require_task_guid: true),
        }

    expect(response.status).to eq(200)
    expect(response.parsed_body["profile"]["require_task_guid"]).to eq(false)
    expect(TzApproval::ProfileRecord.find(profile_id).require_task_guid).to eq(false)
  end

  it "does not delete the default TZ profile" do
    sign_in(admin)
    TzApproval.ensure_default_profile!
    profile = TzApproval::ProfileRecord.find_by!(key: "tz")

    delete "/admin/plugins/tz-approval/profiles/#{profile.id}.json"

    expect(response.status).to eq(422)
    expect(TzApproval::ProfileRecord.exists?(profile.id)).to eq(true)
  end
end
