# frozen_string_literal: true

module TzApproval
  class ProfileRecord < ActiveRecord::Base
    self.table_name = "tz_approval_profiles"

    PREFIX_REGEXP = /\A[a-z0-9_]+\z/
    ICON_REGEXP = /\A[a-z0-9-]+\z/
    BINDING_MODES = %w[tag category].freeze
    JSON_ARRAY_COLUMNS = %i[category_ids allowed_group_ids tags].freeze

    before_validation :normalize_fields
    before_validation :set_default_texts
    after_commit :clear_profiles_cache

    validates :key, :prefix, :label, :binding_mode, :icon, presence: true
    validates :key, :prefix, uniqueness: true
    validates :key, :prefix, format: { with: PREFIX_REGEXP }
    validates :icon, format: { with: ICON_REGEXP }
    validates :binding_mode, inclusion: { in: BINDING_MODES }
    validates :priority, numericality: { only_integer: true }
    validate :prefix_is_immutable
    validate :key_is_immutable
    validate :default_profile_stays_enabled

    scope :ordered, -> { order(:priority, :id) }
    scope :enabled, -> { where(enabled: true) }

    JSON_ARRAY_COLUMNS.each do |column|
      define_method(column) { parse_json_array(self[column]) }
      define_method("#{column}=") { |value| self[column] = normalize_array(value).to_json }
    end

    def status_slug
      prefix.tr("_", "-")
    end

    def system?
      key == TzApproval::DEFAULT_PROFILE_KEY
    end

    def to_profile
      TzApproval::Profile.new(
        id: id,
        key: key,
        prefix: prefix,
        label: label,
        priority: priority,
        categories: category_ids,
        allowed_groups: allowed_group_ids,
        icon: icon,
        enabled: SiteSetting.tz_approval_enabled && enabled,
        binding_mode: binding_mode,
        tags: tags,
        status_slug: status_slug,
        approve_text: approve_text,
        unapprove_text: unapprove_text,
        approved_text: approved_text,
        unapproved_text: unapproved_text,
        approved_by_author_text: approved_by_author_text,
        approved_action_text: approved_action_text,
        unapproved_action_text: unapproved_action_text,
        approved_description: approved_description,
        unapproved_description: unapproved_description,
      )
    end

    def as_json(_options = nil)
      {
        id: id,
        key: key,
        prefix: prefix,
        label: label,
        enabled: enabled,
        priority: priority,
        binding_mode: binding_mode,
        icon: icon,
        category_ids: category_ids,
        allowed_group_ids: allowed_group_ids,
        tags: tags,
        approve_text: approve_text,
        unapprove_text: unapprove_text,
        approved_text: approved_text,
        unapproved_text: unapproved_text,
        approved_by_author_text: approved_by_author_text,
        approved_action_text: approved_action_text,
        unapproved_action_text: unapproved_action_text,
        approved_description: approved_description,
        unapproved_description: unapproved_description,
        system: system?,
      }
    end

    private

    def normalize_fields
      self.key = key.to_s.strip.downcase.tr("-", "_")
      self.prefix = prefix.to_s.strip.downcase.tr("-", "_")
      self.label = label.to_s.strip
      self.binding_mode = binding_mode.to_s.strip
      self.icon = icon.to_s.strip
      self.priority = priority.to_i
      JSON_ARRAY_COLUMNS.each { |column| public_send("#{column}=", public_send(column)) }
    end

    def set_default_texts
      return if label.blank?

      self.approve_text = approve_text.presence || "Одобрить #{label}"
      self.unapprove_text = unapprove_text.presence || "Снять одобрение"
      self.approved_text = approved_text.presence || "#{label} одобрено"
      self.unapproved_text = unapproved_text.presence || "Одобрение #{label} снято"
      self.approved_by_author_text = approved_by_author_text.presence || "#{label} одобрено — Автор темы"
      self.approved_action_text = approved_action_text.presence || "%{username} одобрил #{label}"
      self.unapproved_action_text = unapproved_action_text.presence || "%{username} снял одобрение #{label}"
      self.approved_description = approved_description.presence || "#{label} подтверждено"
      self.unapproved_description = unapproved_description.presence || "Одобрение #{label} снято"
    end

    def prefix_is_immutable
      return unless persisted? && will_save_change_to_prefix?

      errors.add(:prefix, I18n.t("tz_approval.admin.errors.prefix_immutable"))
    end

    def key_is_immutable
      return unless persisted? && will_save_change_to_key?

      errors.add(:key, I18n.t("tz_approval.admin.errors.key_immutable"))
    end

    def default_profile_stays_enabled
      return unless system? && enabled == false

      errors.add(:enabled, I18n.t("tz_approval.admin.errors.default_profile_disable"))
    end

    def parse_json_array(value)
      parsed = JSON.parse(value.presence || "[]")
      normalize_array(parsed)
    rescue JSON::ParserError
      []
    end

    def normalize_array(value)
      Array(value).map { |item| normalize_array_item(item) }.reject(&:blank?).uniq
    end

    def normalize_array_item(item)
      if item.is_a?(Hash)
        item[:id] || item["id"] || item[:name] || item["name"]
      else
        item
      end
    end

    def clear_profiles_cache
      TzApproval.clear_profiles_cache!
    end
  end
end
