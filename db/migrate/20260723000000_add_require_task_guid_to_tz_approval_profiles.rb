# frozen_string_literal: true

class AddRequireTaskGuidToTzApprovalProfiles < ActiveRecord::Migration[7.0]
  def change
    add_column :tz_approval_profiles, :require_task_guid, :boolean, null: false, default: false
  end
end
