# frozen_string_literal: true

# name: discourse-tz-approval
# about: Механизм одобрения ТЗ для тем Discourse
# version: 0.1.0
# authors: ban2zai
# url: https://github.com/ban2zai/discourse-tz-approval
# enabled_site_setting: tz_approval_enabled

%w[
  circle-check
  clipboard-check
  clipboard-list
  file-signature
  stamp
  square-check
].each { |icon| register_svg_icon icon }

register_asset "stylesheets/tz-approval.scss"

module ::TzApproval
  PLUGIN_NAME = "discourse-tz-approval"
  CATEGORY_BINDING_MODE = "category"

  def self.approval_tags
    SiteSetting.tz_approval_tags.to_s.split("|").map(&:strip).reject(&:blank?)
  end

  def self.category_binding_mode?
    SiteSetting.tz_approval_binding_mode.to_s == CATEGORY_BINDING_MODE
  end

  def self.topic_has_approval_tag?(topic)
    (topic.tags.map(&:name) & approval_tags).present?
  end

  def self.topic_in_approval_category?(topic)
    category_ids = SiteSetting.tz_approval_categories_map
    category_ids.present? && category_ids.include?(topic.category_id)
  end

  def self.topic_applicable?(topic)
    return false unless SiteSetting.tz_approval_enabled

    if category_binding_mode?
      topic_in_approval_category?(topic)
    else
      topic_has_approval_tag?(topic)
    end
  end
end

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
      return false unless TzApproval.topic_applicable?(topic)
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
      return false unless TzApproval.topic_applicable?(topic)
      return false unless topic.tz_approved?
      allowed = SiteSetting.tz_approval_allowed_groups_map
      is_staff? ||
        (allowed.present? && @user&.in_any_groups?(allowed)) ||
        (@user&.id == topic.user_id && topic.tz_approved_by_id.to_i == @user&.id)
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

  # ── Search filters ──────────────────────────────────────────────────────────
  tz_applicable_search_filter = lambda do |posts|
    return posts.none unless SiteSetting.tz_approval_enabled

    scoped_posts = posts.where.not(topics: { archetype: Archetype.private_message })

    if TzApproval.category_binding_mode?
      category_ids = SiteSetting.tz_approval_categories_map
      return scoped_posts.none if category_ids.blank?

      scoped_posts.where(topics: { category_id: category_ids })
    else
      tag_ids = Tag.where(name: TzApproval.approval_tags).pluck(:id)
      return scoped_posts.none if tag_ids.empty?

      scoped_posts.where(<<~SQL, tag_ids)
        EXISTS (
          SELECT 1
          FROM topic_tags
          WHERE topic_tags.topic_id = topics.id
            AND topic_tags.tag_id IN (?)
        )
      SQL
    end
  end

  tz_approved_search_filter = lambda do |posts|
    tz_applicable_search_filter
      .call(posts)
      .joins(<<~SQL)
        INNER JOIN topic_custom_fields tz_approval_approved_cf
          ON tz_approval_approved_cf.topic_id = topics.id
         AND tz_approval_approved_cf.name = 'tz_approved'
         AND tz_approval_approved_cf.value = 't'
      SQL
  end

  tz_unapproved_search_filter = lambda do |posts|
    tz_applicable_search_filter
      .call(posts)
      .where(<<~SQL)
        NOT EXISTS (
          SELECT 1
          FROM topic_custom_fields tz_approval_approved_cf
          WHERE tz_approval_approved_cf.topic_id = topics.id
            AND tz_approval_approved_cf.name = 'tz_approved'
            AND tz_approval_approved_cf.value = 't'
        )
      SQL
  end

  register_custom_filter_by_status("tz-approved", &tz_approved_search_filter)
  register_custom_filter_by_status("tz-unapproved", &tz_unapproved_search_filter)
  register_search_advanced_filter(/status:tz-approved/, &tz_approved_search_filter)
  register_search_advanced_filter(/status:tz-unapproved/, &tz_unapproved_search_filter)

  register_modifier(:topics_filter_options) do |results, _guardian|
    results << {
      name: "status:tz-approved",
      description: I18n.t("tz_approval.filter.description.tz_approved"),
      type: "text",
    }
    results << {
      name: "status:tz-unapproved",
      description: I18n.t("tz_approval.filter.description.tz_unapproved"),
      type: "text",
    }
    results
  end

  # ── Routes ───────────────────────────────────────────────────────────────────
  Discourse::Application.routes.append do
    post "/tz-approval/approve"   => "tz_approval/approvals#approve"
    post "/tz-approval/unapprove" => "tz_approval/approvals#unapprove"
  end
end
