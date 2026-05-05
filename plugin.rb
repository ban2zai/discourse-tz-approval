# frozen_string_literal: true

# name: discourse-tz-approval
# about: Механизм одобрения ТЗ для тем Discourse
# version: 0.1.0
# authors: ban2zai
# url: https://github.com/ban2zai/discourse-tz-approval
# enabled_site_setting: tz_approval_enabled

register_svg_icon "stamp"

module ::TzApproval
  PLUGIN_NAME = "discourse-tz-approval"
end

require_relative "lib/tz_approval/engine"

after_initialize do
  require_relative "app/controllers/tz_approval/approvals_controller"

  # ── Custom fields ────────────────────────────────────────────────────────────
  register_topic_custom_field_type("tz_approved",         :boolean)
  register_topic_custom_field_type("tz_approved_by_id",   :integer)
  register_topic_custom_field_type("tz_approved_at",      :string)
  register_topic_custom_field_type("tz_approval_post_id", :integer)

  add_preloaded_topic_list_custom_field("tz_approved")
  add_preloaded_topic_list_custom_field("tz_approved_by_id")
  add_preloaded_topic_list_custom_field("tz_approved_at")

  # ── Геттеры на Topic ─────────────────────────────────────────────────────────
  add_to_class(:topic, :tz_approved?)      { custom_fields["tz_approved"] == true }
  add_to_class(:topic, :tz_approved_by_id) { custom_fields["tz_approved_by_id"] }
  add_to_class(:topic, :tz_approved_at)    { custom_fields["tz_approved_at"] }

  # ── Guardian extension ───────────────────────────────────────────────────────
  module TzApproval::GuardianExtensions
    def can_approve_tz?(topic)
      return false unless SiteSetting.tz_approval_enabled
      return false if topic.tz_approved?
      return true if is_staff?
      allowed = SiteSetting.tz_approval_allowed_groups_map
      return true if allowed.present? && @user&.in_any_groups?(allowed)
      if @user&.id == topic.user_id
        delay = SiteSetting.tz_author_approval_delay.to_i
        return Time.now.to_i - topic.created_at.to_i >= delay
      end
      false
    end

    def ensure_can_approve_tz!(topic)
      raise Discourse::InvalidAccess.new unless can_approve_tz?(topic)
    end

    def can_unapprove_tz?(topic)
      return false unless SiteSetting.tz_approval_enabled
      return false unless topic.tz_approved?
      allowed = SiteSetting.tz_approval_allowed_groups_map
      is_staff? ||
        (allowed.present? && @user&.in_any_groups?(allowed)) ||
        @user&.id == topic.user_id
    end

    def ensure_can_unapprove_tz!(topic)
      raise Discourse::InvalidAccess.new unless can_unapprove_tz?(topic)
    end
  end

  reloadable_patch { ::Guardian.prepend(TzApproval::GuardianExtensions) }

  # ── Сериализаторы ────────────────────────────────────────────────────────────
  add_to_serializer(:topic_view, :tz_approved)     { object.topic.tz_approved? }
  add_to_serializer(:topic_view, :tz_approved_by_id) { object.topic.tz_approved_by_id }
  add_to_serializer(:topic_view, :tz_approved_at)  { object.topic.tz_approved_at }
  add_to_serializer(:topic_view, :tz_approved_by_username) do
    User.find_by(id: object.topic.tz_approved_by_id)&.username
  end
  add_to_serializer(:topic_view, :can_approve_tz)   { scope.can_approve_tz?(object.topic) }
  add_to_serializer(:topic_view, :can_unapprove_tz) { scope.can_unapprove_tz?(object.topic) }

  add_to_serializer(:topic_list_item, :tz_approved) { object.tz_approved? }

  # ── Routes ───────────────────────────────────────────────────────────────────
  Discourse::Application.routes.append do
    mount ::TzApproval::Engine, at: "/tz-approval"
  end

  TzApproval::Engine.routes.draw do
    post "/approve"   => "approvals#approve"
    post "/unapprove" => "approvals#unapprove"
  end
end
