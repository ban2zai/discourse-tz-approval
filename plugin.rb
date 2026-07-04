# frozen_string_literal: true

# name: discourse-tz-approval
# about: Механизм профильного одобрения тем Discourse
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
register_asset "stylesheets/tz-approval-admin.scss"
add_admin_route "tz_approval.admin.title", "tz-approval"

module ::TzApproval
  PLUGIN_NAME = "discourse-tz-approval"
  CATEGORY_BINDING_MODE = "category"
  TAG_BINDING_MODE = "tag"
  DEFAULT_PROFILE_KEY = "tz"
  DEFAULT_PROFILE_PREFIX = "tz"
  NOTIFICATION_TYPE_ID = 167
  PROFILE_PREFIX_REGEXP = /\A[a-z0-9_]+\z/

  Profile =
    Struct.new(
      :id,
      :key,
      :prefix,
      :label,
      :categories,
      :allowed_groups,
      :icon,
      :enabled,
      :binding_mode,
      :tags,
      :status_slug,
      :approve_text,
      :unapprove_text,
      :approved_text,
      :unapproved_text,
      :approved_by_author_text,
      :approved_action_text,
      :unapproved_action_text,
      :approved_description,
      :unapproved_description,
      keyword_init: true,
    )

  def self.safe_prefix(value, fallback)
    prefix = value.to_s.strip.downcase.tr("-", "_")
    prefix.match?(PROFILE_PREFIX_REGEXP) ? prefix : fallback
  end

  def self.safe_icon(value, fallback)
    value.to_s.match?(/\A[a-z0-9-]+\z/) ? value.to_s : fallback
  end

  def self.approval_tags
    SiteSetting.tz_approval_tags.to_s.split("|").map(&:strip).reject(&:blank?)
  end

  def self.profiles_table_exists?
    ActiveRecord::Base.connection.data_source_exists?("tz_approval_profiles")
  rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
    false
  end

  def self.default_profile_attributes
    {
      key: DEFAULT_PROFILE_KEY,
      prefix: DEFAULT_PROFILE_PREFIX,
      label: I18n.t("tz_approval.profiles.tz.label"),
      enabled: true,
      priority: 100,
      binding_mode: SiteSetting.tz_approval_binding_mode.presence || TAG_BINDING_MODE,
      icon: safe_icon(SiteSetting.tz_approval_icon, "file-signature"),
      category_ids: SiteSetting.tz_approval_categories_map,
      allowed_group_ids: SiteSetting.tz_approval_allowed_groups_map,
      tags: approval_tags,
      approve_text: I18n.t("tz_approval.profiles.tz.approve"),
      unapprove_text: I18n.t("tz_approval.profiles.tz.unapprove"),
      approved_text: I18n.t("tz_approval.profiles.tz.approved"),
      unapproved_text: I18n.t("tz_approval.profiles.tz.unapproved"),
      approved_by_author_text: I18n.t("tz_approval.profiles.tz.approved_by_author"),
      approved_action_text: I18n.t("tz_approval.profiles.tz.approved_action"),
      unapproved_action_text: I18n.t("tz_approval.profiles.tz.unapproved_action"),
      approved_description: I18n.t("tz_approval.profiles.tz.approved_description"),
      unapproved_description: I18n.t("tz_approval.profiles.tz.unapproved_description"),
    }
  end

  def self.legacy_default_profile
    attrs = default_profile_attributes

    Profile.new(
      id: nil,
      key: attrs[:key],
      prefix: attrs[:prefix],
      label: attrs[:label],
      categories: attrs[:category_ids],
      allowed_groups: attrs[:allowed_group_ids],
      icon: attrs[:icon],
      enabled: SiteSetting.tz_approval_enabled,
      binding_mode: attrs[:binding_mode],
      tags: attrs[:tags],
      status_slug: attrs[:prefix].tr("_", "-"),
      approve_text: attrs[:approve_text],
      unapprove_text: attrs[:unapprove_text],
      approved_text: attrs[:approved_text],
      unapproved_text: attrs[:unapproved_text],
      approved_by_author_text: attrs[:approved_by_author_text],
      approved_action_text: attrs[:approved_action_text],
      unapproved_action_text: attrs[:unapproved_action_text],
      approved_description: attrs[:approved_description],
      unapproved_description: attrs[:unapproved_description],
    )
  end

  def self.ensure_default_profile!
    return unless profiles_table_exists?
    return if ProfileRecord.exists?(key: DEFAULT_PROFILE_KEY)

    ProfileRecord.create!(default_profile_attributes)
  end

  def self.all_profile_records
    return [] unless profiles_table_exists?

    ensure_default_profile!
    ProfileRecord.ordered.to_a
  end

  def self.all_profiles
    records = all_profile_records
    return [legacy_default_profile] if records.blank?

    records.map(&:to_profile)
  end

  def self.profiles
    all_profiles.select(&:enabled)
  end

  def self.profile_for_key(key)
    profiles.find { |profile| profile.key == key.to_s }
  end

  def self.all_profile_for_key(key)
    all_profiles.find { |profile| profile.key == key.to_s }
  end

  def self.all_profile_for_prefix(prefix)
    safe = safe_prefix(prefix, "")
    all_profiles.find { |profile| profile.prefix == safe }
  end

  def self.topic_has_approval_tag?(topic, profile)
    (topic_tag_names(topic) & profile.tags.map(&:to_s)).present?
  end

  def self.topic_tag_names(topic)
    return [] unless topic.respond_to?(:tags)

    Array(topic.tags).map { |tag| tag.respond_to?(:name) ? tag.name : tag.to_s }.reject(&:blank?)
  end

  def self.topic_in_approval_category?(topic, profile)
    profile.categories.map(&:to_i).include?(topic.category_id)
  end

  def self.topic_applicable_for_profile?(topic, profile)
    return false unless profile&.enabled

    if profile.binding_mode == CATEGORY_BINDING_MODE
      topic_in_approval_category?(topic, profile)
    else
      topic_has_approval_tag?(topic, profile)
    end
  end

  def self.topic_applicable_profile(topic)
    profiles.find { |profile| topic_applicable_for_profile?(topic, profile) }
  end

  def self.topic_applicable?(topic)
    topic_applicable_profile(topic).present?
  end

  def self.field_name(profile, suffix)
    "#{profile.prefix}_#{suffix}"
  end

  def self.approved_field(profile)
    field_name(profile, "approved")
  end

  def self.approved_by_id_field(profile)
    field_name(profile, "approved_by_id")
  end

  def self.approved_at_field(profile)
    field_name(profile, "approved_at")
  end

  def self.approval_post_id_field(profile)
    field_name(profile, "approval_post_id")
  end

  def self.approved_action_code(profile)
    field_name(profile, "approved")
  end

  def self.unapproved_action_code(profile)
    field_name(profile, "unapproved")
  end

  def self.topic_custom_field(topic, field)
    custom_fields = topic.custom_fields if topic.respond_to?(:custom_fields)

    if custom_fields.respond_to?(:key?) && custom_fields.key?(field)
      custom_fields[field]
    else
      TopicCustomField.find_by(topic_id: topic.id, name: field)&.value
    end
  end

  def self.topic_approved_for_profile?(topic, profile)
    value = topic_custom_field(topic, approved_field(profile))
    value == true || value == "true" || value == "t" || value == "1"
  end

  def self.topic_approved_by_id_for_profile(topic, profile)
    topic_custom_field(topic, approved_by_id_field(profile))
  end

  def self.topic_approved_at_for_profile(topic, profile)
    topic_custom_field(topic, approved_at_field(profile))
  end

  def self.profile_payload(topic, guardian = nil, include_username: true)
    profile = topic_applicable_profile(topic)
    payload = {
      approval_profile_key: nil,
      approval_profile_prefix: nil,
      approval_label: nil,
      approval_icon: nil,
      approval_approve_text: nil,
      approval_unapprove_text: nil,
      approval_approved_text: nil,
      approval_approved_by_author_text: nil,
      approved: false,
      approved_by_id: nil,
      approved_at: nil,
    }

    if profile
      approved_by_id = topic_approved_by_id_for_profile(topic, profile)
      payload.merge!(
        approval_profile_key: profile.key,
        approval_profile_prefix: profile.prefix,
        approval_label: profile.label,
        approval_icon: profile.icon,
        approval_approve_text: profile.approve_text,
        approval_unapprove_text: profile.unapprove_text,
        approval_approved_text: profile.approved_text,
        approval_approved_by_author_text: profile.approved_by_author_text,
        approved: topic_approved_for_profile?(topic, profile),
        approved_by_id: approved_by_id,
        approved_at: topic_approved_at_for_profile(topic, profile),
      )

      payload[:approved_by_username] = User.find_by(id: approved_by_id)&.username if include_username
    end

    if guardian
      payload[:can_approve] = guardian.can_approve_tz?(topic)
      payload[:can_unapprove] = guardian.can_unapprove_tz?(topic)
    end

    payload
  end

  def self.tz_payload(topic)
    profile = all_profile_for_key(DEFAULT_PROFILE_KEY) || legacy_default_profile
    approved_by_id = topic_approved_by_id_for_profile(topic, profile)

    {
      tz_approved: topic_approved_for_profile?(topic, profile),
      tz_approved_by_id: approved_by_id,
      tz_approved_at: topic_approved_at_for_profile(topic, profile),
      tz_approved_by_username: User.find_by(id: approved_by_id)&.username,
    }
  end
end

require_relative "app/models/tz_approval/profile_record"

after_initialize do
  require_relative "app/controllers/tz_approval/approvals_controller"
  require_relative "app/controllers/tz_approval/admin/profiles_controller"

  Notification.types[:tz_approval] = TzApproval::NOTIFICATION_TYPE_ID

  # ── Custom fields ────────────────────────────────────────────────────────────
  TzApproval.all_profiles.each do |profile|
    register_topic_custom_field_type(TzApproval.approved_field(profile), :boolean)
    register_topic_custom_field_type(TzApproval.approved_by_id_field(profile), :integer)
    register_topic_custom_field_type(TzApproval.approved_at_field(profile), :string)
    register_topic_custom_field_type(TzApproval.approval_post_id_field(profile), :integer)

    add_preloaded_topic_list_custom_field(TzApproval.approved_field(profile))
    add_preloaded_topic_list_custom_field(TzApproval.approved_by_id_field(profile))
    add_preloaded_topic_list_custom_field(TzApproval.approved_at_field(profile))
  end

  # ── Геттеры на Topic ─────────────────────────────────────────────────────────
  add_to_class(:topic, :tz_approval_profile) { TzApproval.topic_applicable_profile(self) }
  add_to_class(:topic, :tz_approval_approved?) do
    profile = tz_approval_profile
    profile.present? && TzApproval.topic_approved_for_profile?(self, profile)
  end
  add_to_class(:topic, :tz_approved?) do
    profile = TzApproval.all_profile_for_key(TzApproval::DEFAULT_PROFILE_KEY) || TzApproval.legacy_default_profile
    TzApproval.topic_approved_for_profile?(self, profile)
  end
  add_to_class(:topic, :tz_approved_by_id) do
    profile = TzApproval.all_profile_for_key(TzApproval::DEFAULT_PROFILE_KEY) || TzApproval.legacy_default_profile
    TzApproval.topic_approved_by_id_for_profile(self, profile)
  end
  add_to_class(:topic, :tz_approved_at) do
    profile = TzApproval.all_profile_for_key(TzApproval::DEFAULT_PROFILE_KEY) || TzApproval.legacy_default_profile
    TzApproval.topic_approved_at_for_profile(self, profile)
  end

  # ── Guardian extension ───────────────────────────────────────────────────────
  module TzApproval::GuardianExtensions
    def can_approve_tz?(topic)
      profile = TzApproval.topic_applicable_profile(topic)
      return false unless profile
      return false if TzApproval.topic_approved_for_profile?(topic, profile)
      return true if is_staff?

      allowed = profile.allowed_groups.map(&:to_i)
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
      profile = TzApproval.topic_applicable_profile(topic)
      return false unless profile
      return false unless TzApproval.topic_approved_for_profile?(topic, profile)

      allowed = profile.allowed_groups.map(&:to_i)
      approved_by_id = TzApproval.topic_approved_by_id_for_profile(topic, profile)

      is_staff? ||
        (allowed.present? && @user&.in_any_groups?(allowed)) ||
        (@user&.id == topic.user_id && approved_by_id.to_i == @user&.id)
    end

    def ensure_can_unapprove_tz!(topic)
      raise Discourse::InvalidAccess.new unless can_unapprove_tz?(topic)
    end
  end

  reloadable_patch { ::Guardian.prepend(TzApproval::GuardianExtensions) }

  # ── Сериализаторы ────────────────────────────────────────────────────────────
  add_to_serializer(:site, :tz_approval_profiles) do
    TzApproval.profiles.map do |profile|
      {
        key: profile.key,
        prefix: profile.prefix,
        status_slug: profile.status_slug,
        label: profile.label,
        icon: profile.icon,
        approved_text: profile.approved_text,
        unapproved_text: profile.unapproved_text,
        approved_description: profile.approved_description,
        unapproved_description: profile.unapproved_description,
      }
    end
  end

  %i[
    approval_profile_key
    approval_profile_prefix
    approval_label
    approval_icon
    approval_approve_text
    approval_unapprove_text
    approval_approved_text
    approval_approved_by_author_text
    approved
    approved_by_id
    approved_at
  ].each do |field|
    add_to_serializer(:topic_view, field) do
      TzApproval.profile_payload(object.topic, nil, include_username: false)[field]
    end

    add_to_serializer(:topic_list_item, field) do
      TzApproval.profile_payload(object, nil, include_username: false)[field]
    end
  end

  add_to_serializer(:topic_view, :approved_by_username) do
    TzApproval.profile_payload(object.topic, nil, include_username: true)[:approved_by_username]
  end

  add_to_serializer(:topic_view, :can_approve) do
    TzApproval.profile_payload(object.topic, scope, include_username: false)[:can_approve]
  end

  add_to_serializer(:topic_view, :can_unapprove) do
    TzApproval.profile_payload(object.topic, scope, include_username: false)[:can_unapprove]
  end

  add_to_serializer(:topic_view, :tz_approved) { TzApproval.tz_payload(object.topic)[:tz_approved] }
  add_to_serializer(:topic_view, :tz_approved_by_id) do
    TzApproval.tz_payload(object.topic)[:tz_approved_by_id]
  end
  add_to_serializer(:topic_view, :tz_approved_at) { TzApproval.tz_payload(object.topic)[:tz_approved_at] }
  add_to_serializer(:topic_view, :tz_approved_by_username) do
    TzApproval.tz_payload(object.topic)[:tz_approved_by_username]
  end
  add_to_serializer(:topic_view, :can_approve_tz) { scope.can_approve_tz?(object.topic) }
  add_to_serializer(:topic_view, :can_unapprove_tz) { scope.can_unapprove_tz?(object.topic) }

  add_to_serializer(:topic_list_item, :tz_approved) { object.tz_approved? }

  # ── Search filters ──────────────────────────────────────────────────────────
  profile_applicable_search_filter = lambda do |posts, profile|
    return posts.none unless SiteSetting.tz_approval_enabled
    return posts.none unless profile&.enabled

    scoped_posts = posts.where.not(topics: { archetype: Archetype.private_message })

    if profile.binding_mode == TzApproval::CATEGORY_BINDING_MODE
      category_ids = profile.categories.map(&:to_i)
      return scoped_posts.none if category_ids.blank?

      scoped_posts.where(topics: { category_id: category_ids })
    else
      tag_ids = Tag.where(name: profile.tags.map(&:to_s)).pluck(:id)
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

  profile_approved_search_filter = lambda do |posts, profile|
    profile_applicable_search_filter
      .call(posts, profile)
      .joins(<<~SQL)
        INNER JOIN topic_custom_fields #{profile.prefix}_approval_approved_cf
          ON #{profile.prefix}_approval_approved_cf.topic_id = topics.id
         AND #{profile.prefix}_approval_approved_cf.name = '#{TzApproval.approved_field(profile)}'
         AND #{profile.prefix}_approval_approved_cf.value IN ('t', 'true', '1')
      SQL
  end

  profile_unapproved_search_filter = lambda do |posts, profile|
    profile_applicable_search_filter
      .call(posts, profile)
      .where(<<~SQL)
        NOT EXISTS (
          SELECT 1
          FROM topic_custom_fields #{profile.prefix}_approval_approved_cf
          WHERE #{profile.prefix}_approval_approved_cf.topic_id = topics.id
            AND #{profile.prefix}_approval_approved_cf.name = '#{TzApproval.approved_field(profile)}'
            AND #{profile.prefix}_approval_approved_cf.value IN ('t', 'true', '1')
        )
      SQL
  end

  apply_status_filter = lambda do |posts, raw_status|
    status = raw_status.to_s
    state = status.end_with?("-unapproved") ? "unapproved" : "approved"
    prefix = status.sub(/-(?:un)?approved\z/, "").tr("-", "_")
    profile = TzApproval.all_profile_for_prefix(prefix)
    next posts.none unless profile

    if state == "unapproved"
      profile_unapproved_search_filter.call(posts, profile)
    else
      profile_approved_search_filter.call(posts, profile)
    end
  end

  register_search_advanced_filter(/status:([a-z0-9-]+-(?:approved|unapproved))/) do |posts, status|
    apply_status_filter.call(posts, status)
  end

  TzApproval.all_profiles.each do |profile|
    register_custom_filter_by_status("#{profile.status_slug}-approved") do |posts|
      current_profile = TzApproval.all_profile_for_prefix(profile.prefix)
      profile_approved_search_filter.call(posts, current_profile)
    end

    register_custom_filter_by_status("#{profile.status_slug}-unapproved") do |posts|
      current_profile = TzApproval.all_profile_for_prefix(profile.prefix)
      profile_unapproved_search_filter.call(posts, current_profile)
    end
  end

  register_modifier(:topics_filter_options) do |results, _guardian|
    TzApproval.profiles.each do |profile|
      results << {
        name: "status:#{profile.status_slug}-approved",
        description: I18n.t("tz_approval.filter.description.approved", label: profile.label),
        type: "text",
      }
      results << {
        name: "status:#{profile.status_slug}-unapproved",
        description: I18n.t("tz_approval.filter.description.unapproved", label: profile.label),
        type: "text",
      }
    end

    results
  end

  # ── Routes ───────────────────────────────────────────────────────────────────
  Discourse::Application.routes.append do
    post "/tz-approval/approve" => "tz_approval/approvals#approve"
    post "/tz-approval/unapprove" => "tz_approval/approvals#unapprove"

    get "/admin/plugins/tz-approval" => "admin/plugins#index", constraints: StaffConstraint.new
    get "/admin/plugins/tz-approval/profiles" => "tz_approval/admin/profiles#index",
        defaults: { format: :json }
    post "/admin/plugins/tz-approval/profiles" => "tz_approval/admin/profiles#create",
         defaults: { format: :json }
    put "/admin/plugins/tz-approval/profiles/:id" => "tz_approval/admin/profiles#update",
        defaults: { format: :json }
    delete "/admin/plugins/tz-approval/profiles/:id" => "tz_approval/admin/profiles#destroy",
           defaults: { format: :json }
  end
end
