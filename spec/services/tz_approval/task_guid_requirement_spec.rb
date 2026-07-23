# frozen_string_literal: true

RSpec.describe TzApproval::TaskGuidRequirement do
  fab!(:user) { Fabricate(:user) }
  fab!(:admin) { Fabricate(:admin) }

  let(:category_id) { 42 }
  let(:guid_plugin) do
    Class.new.tap { |plugin| plugin.const_set(:FIELD_NAME, "test_task_guid") }
  end

  before do
    TzApproval::ProfileRecord.delete_all
    TzApproval.clear_profiles_cache!

    TzApproval::ProfileRecord.create!(
      key: "second_line",
      prefix: "second_line",
      label: "Вторая линия",
      priority: 100,
      binding_mode: "category",
      category_ids: [category_id],
      require_task_guid: true,
    )

    described_class.stubs(:guid_plugin).returns(guid_plugin)
    described_class.stubs(:guid_plugin_enabled?).returns(true)
    guid_plugin.stubs(:normalize_guid).returns("guid-1")
    guid_plugin.stubs(:valid_create_signature?).returns(true)
    guid_plugin.stubs(:topic_for_guid).returns(nil)
  end

  describe ".creation_allowed?" do
    def creation_allowed(user:, opts: {})
      described_class.creation_allowed?(
        user: user,
        category_id: category_id,
        tag_inputs: [],
        opts: opts,
      )
    end

    it "allows a valid signed and unique GUID" do
      expect(creation_allowed(user: user, opts: { task_guid: "guid-1" })).to eq(true)
    end

    it "blocks a missing or invalid GUID" do
      guid_plugin.stubs(:normalize_guid).returns(nil)

      expect(creation_allowed(user: user)).to eq(false)
    end

    it "blocks an invalid create signature" do
      guid_plugin.stubs(:valid_create_signature?).returns(false)

      expect(creation_allowed(user: user, opts: { task_guid: "guid-1" })).to eq(false)
    end

    it "blocks a GUID that is already linked to another topic" do
      guid_plugin.stubs(:topic_for_guid).returns(Struct.new(:id).new(123))

      expect(creation_allowed(user: user, opts: { task_guid: "guid-1" })).to eq(false)
    end

    it "fails closed when the GUID plugin contract is unavailable" do
      described_class.stubs(:guid_plugin).returns(nil)

      expect(creation_allowed(user: user, opts: { task_guid: "guid-1" })).to eq(false)
    end

    it "fails closed when the GUID plugin is disabled" do
      described_class.stubs(:guid_plugin_enabled?).returns(false)

      expect(creation_allowed(user: user, opts: { task_guid: "guid-1" })).to eq(false)
    end

    it "allows an administrator to bypass the requirement" do
      described_class.stubs(:guid_plugin).returns(nil)

      expect(creation_allowed(user: admin)).to eq(true)
    end

    it "does not apply outside the protected effective profile" do
      expect(
        described_class.creation_allowed?(
          user: user,
          category_id: 999,
          tag_inputs: [],
          opts: {},
        ),
      ).to eq(true)
    end

    it "does not apply when the effective profile flag is off" do
      TzApproval::ProfileRecord.find_by!(key: "second_line").update!(require_task_guid: false)
      described_class.stubs(:guid_plugin).returns(nil)

      expect(creation_allowed(user: user)).to eq(true)
    end

    it "does not apply when approval is globally disabled" do
      SiteSetting.tz_approval_enabled = false
      described_class.stubs(:guid_plugin).returns(nil)

      expect(creation_allowed(user: user)).to eq(true)
    ensure
      SiteSetting.tz_approval_enabled = true
    end

    it "does not apply when the effective profile is disabled" do
      TzApproval::ProfileRecord.find_by!(key: "second_line").update!(enabled: false)
      described_class.stubs(:guid_plugin).returns(nil)

      expect(creation_allowed(user: user)).to eq(true)
    end

    it "uses the higher-priority tag profile for final tags" do
      TzApproval::ProfileRecord.create!(
        key: "tag_first",
        prefix: "tag_first",
        label: "Тег раньше",
        priority: 10,
        binding_mode: "tag",
        tags: ["important"],
      )
      described_class.stubs(:guid_plugin).returns(nil)

      expect(
        described_class.creation_allowed?(
          user: user,
          category_id: category_id,
          tag_inputs: [{ name: "important" }],
          opts: {},
        ),
      ).to eq(true)
    end
  end

  describe ".category_change_allowed?" do
    def category_change_allowed(user:, guid:)
      topic = Struct.new(:custom_fields).new({ "test_task_guid" => guid })

      described_class.category_change_allowed?(
        topic: topic,
        user: user,
        category_id: category_id,
        tag_inputs: [],
      )
    end

    it "allows a stored or manually added GUID" do
      expect(category_change_allowed(user: user, guid: "guid-1")).to eq(true)
    end

    it "blocks a category change without a stored GUID" do
      guid_plugin.stubs(:normalize_guid).returns(nil)

      expect(category_change_allowed(user: user, guid: nil)).to eq(false)
    end

    it "allows moving out of a protected category" do
      topic = Struct.new(:custom_fields).new({ "test_task_guid" => nil })

      expect(
        described_class.category_change_allowed?(
          topic: topic,
          user: user,
          category_id: 999,
          tag_inputs: [],
        ),
      ).to eq(true)
    end

    it "allows an administrator to bypass the requirement" do
      described_class.stubs(:guid_plugin).returns(nil)

      expect(category_change_allowed(user: admin, guid: nil)).to eq(true)
    end
  end
end
