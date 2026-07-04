# frozen_string_literal: true

class CreateTzApprovalProfiles < ActiveRecord::Migration[7.0]
  def change
    create_table :tz_approval_profiles do |t|
      t.string :key, null: false
      t.string :prefix, null: false
      t.string :label, null: false
      t.boolean :enabled, null: false, default: true
      t.integer :priority, null: false, default: 100
      t.string :binding_mode, null: false, default: "category"
      t.string :icon, null: false, default: "file-signature"
      t.text :category_ids, null: false, default: "[]"
      t.text :allowed_group_ids, null: false, default: "[]"
      t.text :tags, null: false, default: "[]"
      t.string :approve_text, null: false
      t.string :unapprove_text, null: false
      t.string :approved_text, null: false
      t.string :unapproved_text, null: false
      t.string :approved_by_author_text, null: false
      t.string :approved_action_text, null: false
      t.string :unapproved_action_text, null: false
      t.string :approved_description, null: false
      t.string :unapproved_description, null: false

      t.timestamps
    end

    add_index :tz_approval_profiles, :key, unique: true
    add_index :tz_approval_profiles, :prefix, unique: true
    add_index :tz_approval_profiles, %i[enabled priority]
  end
end
