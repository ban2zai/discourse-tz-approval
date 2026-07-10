# frozen_string_literal: true

RSpec.describe TzApproval::ProfileRecord do
  before do
    described_class.delete_all
    TzApproval.clear_profiles_cache!
  end

  it "creates the default TZ profile from legacy settings" do
    SiteSetting.tz_approval_binding_mode = "category"

    TzApproval.ensure_default_profile!

    profile = described_class.find_by!(key: "tz")
    expect(profile.prefix).to eq("tz")
    expect(profile.label).to eq("ТЗ")
    expect(profile.binding_mode).to eq("category")
    expect(profile.author_locked_action_text).to eq(
      "%{username} запретил автору самостоятельно одобрять %{label}",
    )
    expect(profile.author_unlocked_action_text).to eq(
      "%{username} разрешил автору самостоятельно одобрять %{label}",
    )
  end

  it "fills author lock texts for a minimally configured profile" do
    profile = described_class.create!(key: "line", prefix: "line", label: "Линия")

    expect(profile.author_locked_action_text).to eq(
      "%{username} запретил автору самостоятельно одобрять Линия",
    )
    expect(profile.author_unlocked_action_text).to eq(
      "%{username} разрешил автору самостоятельно одобрять Линия",
    )
  end

  it "backfills legacy English texts on the default TZ profile" do
    described_class.create!(
      key: "tz",
      prefix: "tz",
      label: "TZ",
      enabled: true,
      priority: 100,
      binding_mode: "tag",
      icon: "file-signature",
      approve_text: "Approve TZ",
      unapprove_text: "Unapprove TZ",
      approved_text: "TZ approved",
      unapproved_text: "TZ approval removed",
      approved_by_author_text: "TZ approved — Topic author",
      approved_action_text: "%{username} approved this TZ",
      unapproved_action_text: "%{username} unapproved this TZ",
      approved_description: "TZ confirmed",
      unapproved_description: "TZ confirmation removed",
    )

    TzApproval.ensure_default_profile!

    profile = described_class.find_by!(key: "tz")
    expect(profile.label).to eq("ТЗ")
    expect(profile.approve_text).to eq("Одобрить ТЗ")
    expect(profile.approved_action_text).to eq("%{username} одобрил это ТЗ")
  end

  it "does not overwrite customized texts on the default TZ profile" do
    described_class.create!(
      key: "tz",
      prefix: "tz",
      label: "Мой профиль",
      enabled: true,
      priority: 100,
      binding_mode: "tag",
      icon: "file-signature",
      approve_text: "Мой текст",
    )

    TzApproval.ensure_default_profile!

    profile = described_class.find_by!(key: "tz")
    expect(profile.label).to eq("Мой профиль")
    expect(profile.approve_text).to eq("Мой текст")
  end

  it "backfills blank author lock texts on the default profile" do
    TzApproval.ensure_default_profile!
    profile = described_class.find_by!(key: "tz")
    profile.update_columns(author_locked_action_text: "", author_unlocked_action_text: "")
    TzApproval.clear_profiles_cache!

    TzApproval.ensure_default_profile!

    profile.reload
    expect(profile.author_locked_action_text).to eq(
      TzApproval::RUSSIAN_DEFAULT_PROFILE_TEXTS[:author_locked_action_text],
    )
    expect(profile.author_unlocked_action_text).to eq(
      TzApproval::RUSSIAN_DEFAULT_PROFILE_TEXTS[:author_unlocked_action_text],
    )
  end

  it "exposes author lock texts through JSON, profile structs, and cache" do
    profile =
      described_class.create!(
        key: "line",
        prefix: "line",
        label: "Линия",
        author_locked_action_text: "LOCK %{label}",
        author_unlocked_action_text: "UNLOCK %{label}",
      )

    expect(profile.as_json).to include(
      author_locked_action_text: "LOCK %{label}",
      author_unlocked_action_text: "UNLOCK %{label}",
    )
    expect(profile.to_profile.author_locked_action_text).to eq("LOCK %{label}")
    expect(TzApproval.all_profile_for_key("line").author_unlocked_action_text).to eq(
      "UNLOCK %{label}",
    )
  end

  it "validates key and prefix format" do
    profile = described_class.new(key: "bad-prefix!", prefix: "bad-prefix!", label: "Bad")

    expect(profile).not_to be_valid
    expect(profile.errors[:key]).to be_present
    expect(profile.errors[:prefix]).to be_present
  end

  it "does not allow prefix changes after creation" do
    profile = described_class.create!(key: "line", prefix: "line", label: "Line")

    profile.prefix = "other"

    expect(profile).not_to be_valid
    expect(profile.errors[:prefix]).to be_present
  end

  it "does not allow disabling the default TZ profile" do
    TzApproval.ensure_default_profile!
    profile = described_class.find_by!(key: "tz")

    profile.enabled = false

    expect(profile).not_to be_valid
    expect(profile.errors[:enabled]).to be_present
  end

  it "does not seed the default profile while reading profiles" do
    expect { TzApproval.all_profiles }.not_to change { described_class.count }
    expect(TzApproval.all_profiles.first.key).to eq("tz")
  end

  it "invalidates cached profiles after profile changes" do
    profile = described_class.create!(key: "line", prefix: "line", label: "Line")

    expect(TzApproval.all_profile_for_key("line").label).to eq("Line")

    profile.update!(label: "Updated line")
    expect(TzApproval.all_profile_for_key("line").label).to eq("Updated line")

    profile.destroy!
    expect(TzApproval.all_profile_for_key("line")).to be_nil
  end

  it "applies the global enabled setting outside the cached profile attributes" do
    described_class.create!(key: "line", prefix: "line", label: "Line", enabled: true)

    expect(TzApproval.all_profile_for_key("line").enabled).to eq(true)

    SiteSetting.tz_approval_enabled = false

    expect(TzApproval.all_profile_for_key("line").enabled).to eq(false)
  ensure
    SiteSetting.tz_approval_enabled = true
  end

  it "matches approval tags when topic list tags are plain strings" do
    profile = TzApproval::Profile.new(enabled: true, binding_mode: "tag", tags: ["tz"])
    topic = Struct.new(:tags).new(["tz"])

    expect(TzApproval.topic_applicable_for_profile?(topic, profile)).to eq(true)
  end

  it "matches approval tags when topic tags are tag-like objects" do
    profile = TzApproval::Profile.new(enabled: true, binding_mode: "tag", tags: ["tz"])
    tag = Struct.new(:name).new("tz")
    topic = Struct.new(:tags).new([tag])

    expect(TzApproval.topic_applicable_for_profile?(topic, profile)).to eq(true)
  end
end
