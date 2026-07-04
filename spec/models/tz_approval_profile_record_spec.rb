# frozen_string_literal: true

RSpec.describe TzApproval::ProfileRecord do
  before do
    described_class.delete_all
  end

  it "creates the default TZ profile from legacy settings" do
    SiteSetting.tz_approval_binding_mode = "category"

    TzApproval.ensure_default_profile!

    profile = described_class.find_by!(key: "tz")
    expect(profile.prefix).to eq("tz")
    expect(profile.label).to eq("ТЗ")
    expect(profile.binding_mode).to eq("category")
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
end
