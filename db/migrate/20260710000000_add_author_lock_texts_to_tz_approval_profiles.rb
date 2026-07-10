# frozen_string_literal: true

class AddAuthorLockTextsToTzApprovalProfiles < ActiveRecord::Migration[7.0]
  def up
    add_column :tz_approval_profiles, :author_locked_action_text, :string
    add_column :tz_approval_profiles, :author_unlocked_action_text, :string

    execute <<~SQL
      UPDATE tz_approval_profiles
      SET author_locked_action_text = '%{username} запретил автору самостоятельно одобрять %{label}'
      WHERE author_locked_action_text IS NULL
    SQL

    execute <<~SQL
      UPDATE tz_approval_profiles
      SET author_unlocked_action_text = '%{username} разрешил автору самостоятельно одобрять %{label}'
      WHERE author_unlocked_action_text IS NULL
    SQL
  end

  def down
    remove_column :tz_approval_profiles, :author_unlocked_action_text
    remove_column :tz_approval_profiles, :author_locked_action_text
  end
end
