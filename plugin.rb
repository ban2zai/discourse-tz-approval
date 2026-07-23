# frozen_string_literal: true

# name: discourse-tz-approval
# about: Механизм профильного одобрения тем Discourse
# version: 0.1.0
# authors: ban2zai
# url: https://github.com/ban2zai/discourse-tz-approval
# enabled_site_setting: tz_approval_enabled

require "digest"

%w[
  circle-check
  clipboard-check
  clipboard-list
  file-signature
  stamp
  square-check
  lock
  lock-open
  user-plus
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
  SS_PROFILE_PREFIX = "ss"
  SECOND_LINE_PROFILE_PREFIX = "second_line"
  SOLVED_TABLE_NAME = "discourse_solved_solved_topics"
  PROFILE_CACHE_KEY = "profiles_v2"
  NOTIFICATION_TYPE_ID = 167
  PROFILE_PREFIX_REGEXP = /\A[a-z0-9_]+\z/
  AUTHOR_LOCK_PROFILE_TEXT_FIELDS = %i[
    author_locked_action_text
    author_unlocked_action_text
  ].freeze
  PROFILE_CACHE_SCHEMA_FIELDS = (AUTHOR_LOCK_PROFILE_TEXT_FIELDS + %i[require_task_guid]).freeze
  DEFAULT_PROFILE_TEXT_FIELDS = %i[
    label
    approve_text
    unapprove_text
    approved_text
    unapproved_text
    approved_by_author_text
    approved_action_text
    unapproved_action_text
    author_locked_action_text
    author_unlocked_action_text
    approved_description
    unapproved_description
  ].freeze
  RUSSIAN_DEFAULT_PROFILE_TEXTS = {
    label: "ТЗ",
    approve_text: "Одобрить ТЗ",
    unapprove_text: "Снять одобрение",
    approved_text: "ТЗ одобрено",
    unapproved_text: "Одобрение ТЗ снято",
    approved_by_author_text: "ТЗ одобрено — Автор темы",
    approved_action_text: "%{username} одобрил это ТЗ",
    unapproved_action_text: "%{username} снял одобрение с этого ТЗ",
    author_locked_action_text: "%{username} запретил автору самостоятельно одобрять %{label}",
    author_unlocked_action_text: "%{username} разрешил автору самостоятельно одобрять %{label}",
    approved_description: "ТЗ подтверждено",
    unapproved_description: "ТЗ снято с подтверждения",
  }.freeze
  LEGACY_ENGLISH_DEFAULT_PROFILE_TEXTS = {
    label: "TZ",
    approve_text: "Approve TZ",
    unapprove_text: "Unapprove TZ",
    approved_text: "TZ approved",
    unapproved_text: "TZ approval removed",
    approved_by_author_text: "TZ approved — Topic author",
    approved_action_text: "%{username} approved this TZ",
    unapproved_action_text: "%{username} unapproved this TZ",
    approved_description: "TZ confirmed",
    unapproved_description: "TZ confirmation removed",
  }.freeze

  Profile =
    Struct.new(
      :id,
      :key,
      :prefix,
      :label,
      :priority,
      :categories,
      :allowed_groups,
      :icon,
      :enabled,
      :binding_mode,
      :require_task_guid,
      :tags,
      :status_slug,
      :approve_text,
      :unapprove_text,
      :approved_text,
      :unapproved_text,
      :approved_by_author_text,
      :approved_action_text,
      :unapproved_action_text,
      :author_locked_action_text,
      :author_unlocked_action_text,
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
    return @profiles_table_exists unless @profiles_table_exists.nil?

    @profiles_table_exists = ActiveRecord::Base.connection.data_source_exists?("tz_approval_profiles")
  rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
    false
  end

  def self.profile_cache
    @profile_cache ||= DistributedCache.new("tz_approval_profiles")
  end

  def self.clear_profiles_cache!
    profile_cache.delete(PROFILE_CACHE_KEY)
  end

  def self.profile_record_cache_attributes(record)
    record.as_json.except(:system)
  end

  def self.profile_text_schema_current?
    available_columns = ProfileRecord.column_names
    PROFILE_CACHE_SCHEMA_FIELDS.all? { |field| available_columns.include?(field.to_s) }
  end

  def self.profile_from_cache_attributes(attrs)
    attrs = attrs.with_indifferent_access

    Profile.new(
      id: attrs[:id],
      key: attrs[:key],
      prefix: attrs[:prefix],
      label: attrs[:label],
      priority: attrs[:priority],
      categories: Array(attrs[:category_ids]),
      allowed_groups: Array(attrs[:allowed_group_ids]),
      icon: attrs[:icon],
      enabled: SiteSetting.tz_approval_enabled && attrs[:enabled],
      binding_mode: attrs[:binding_mode],
      require_task_guid:
        attrs[:binding_mode] == CATEGORY_BINDING_MODE && attrs[:require_task_guid] == true,
      tags: Array(attrs[:tags]),
      status_slug: attrs[:prefix].to_s.tr("_", "-"),
      approve_text: attrs[:approve_text],
      unapprove_text: attrs[:unapprove_text],
      approved_text: attrs[:approved_text],
      unapproved_text: attrs[:unapproved_text],
      approved_by_author_text: attrs[:approved_by_author_text],
      approved_action_text: attrs[:approved_action_text],
      unapproved_action_text: attrs[:unapproved_action_text],
      author_locked_action_text: attrs[:author_locked_action_text],
      author_unlocked_action_text: attrs[:author_unlocked_action_text],
      approved_description: attrs[:approved_description],
      unapproved_description: attrs[:unapproved_description],
    )
  end

  def self.default_profile_attributes
    {
      key: DEFAULT_PROFILE_KEY,
      prefix: DEFAULT_PROFILE_PREFIX,
      label: RUSSIAN_DEFAULT_PROFILE_TEXTS[:label],
      enabled: true,
      priority: 100,
      binding_mode: SiteSetting.tz_approval_binding_mode.presence || TAG_BINDING_MODE,
      require_task_guid: false,
      icon: safe_icon(SiteSetting.tz_approval_icon, "file-signature"),
      category_ids: SiteSetting.tz_approval_categories_map,
      allowed_group_ids: SiteSetting.tz_approval_allowed_groups_map,
      tags: approval_tags,
    }.merge(RUSSIAN_DEFAULT_PROFILE_TEXTS.reject { |field, _value| field == :label })
  end

  def self.legacy_default_profile
    attrs = default_profile_attributes

    Profile.new(
      id: nil,
      key: attrs[:key],
      prefix: attrs[:prefix],
      label: attrs[:label],
      priority: attrs[:priority],
      categories: attrs[:category_ids],
      allowed_groups: attrs[:allowed_group_ids],
      icon: attrs[:icon],
      enabled: SiteSetting.tz_approval_enabled,
      binding_mode: attrs[:binding_mode],
      require_task_guid: false,
      tags: attrs[:tags],
      status_slug: attrs[:prefix].tr("_", "-"),
      approve_text: attrs[:approve_text],
      unapprove_text: attrs[:unapprove_text],
      approved_text: attrs[:approved_text],
      unapproved_text: attrs[:unapproved_text],
      approved_by_author_text: attrs[:approved_by_author_text],
      approved_action_text: attrs[:approved_action_text],
      unapproved_action_text: attrs[:unapproved_action_text],
      author_locked_action_text: attrs[:author_locked_action_text],
      author_unlocked_action_text: attrs[:author_unlocked_action_text],
      approved_description: attrs[:approved_description],
      unapproved_description: attrs[:unapproved_description],
    )
  end

  def self.ensure_default_profile!
    return unless profiles_table_exists?

    profile = ProfileRecord.find_by(key: DEFAULT_PROFILE_KEY)

    if profile
      backfill_default_profile_texts!(profile)
    else
      available_fields = ProfileRecord.column_names.map(&:to_sym)
      ProfileRecord.create!(default_profile_attributes.slice(*available_fields))
    end
  rescue ActiveRecord::RecordNotUnique
    ProfileRecord.find_by(key: DEFAULT_PROFILE_KEY)
  end

  def self.ensure_default_profile_safely!
    ensure_default_profile!
  rescue ActiveRecord::NoDatabaseError, ActiveRecord::ReadOnlyError, ActiveRecord::StatementInvalid => e
    Rails.logger.warn("tz-approval: не удалось создать дефолтный профиль: #{e.class}: #{e.message}")
  end

  def self.backfill_default_profile_texts!(profile)
    updates =
      DEFAULT_PROFILE_TEXT_FIELDS.each_with_object({}) do |field, attrs|
        next unless profile.has_attribute?(field)

        value = profile.public_send(field)
        next unless value.blank? || value == LEGACY_ENGLISH_DEFAULT_PROFILE_TEXTS[field]

        attrs[field] = RUSSIAN_DEFAULT_PROFILE_TEXTS[field]
      end

    profile.update!(updates) if updates.present?
  end

  def self.all_profile_records
    return [] unless profiles_table_exists?

    ProfileRecord.ordered.to_a
  end

  def self.all_profile_attributes
    return [] unless profiles_table_exists?

    unless profile_text_schema_current?
      return ProfileRecord.ordered.map { |record| profile_record_cache_attributes(record) }
    end

    cached = profile_cache[PROFILE_CACHE_KEY]
    return cached if cached

    ProfileRecord.ordered.map { |record| profile_record_cache_attributes(record) }.tap do |attrs|
      profile_cache[PROFILE_CACHE_KEY] = attrs
    end
  end

  def self.all_profiles
    attrs = all_profile_attributes
    return [legacy_default_profile] if attrs.blank?

    attrs.map { |profile_attrs| profile_from_cache_attributes(profile_attrs) }
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

  def self.profile_applicable_for_values?(profile, category_id:, tag_names:)
    return false unless profile&.enabled

    if profile.binding_mode == CATEGORY_BINDING_MODE
      Array(profile.categories).map(&:to_i).include?(category_id.to_i)
    else
      (Array(tag_names).map(&:to_s) & Array(profile.tags).map(&:to_s)).present?
    end
  end

  def self.applicable_profile_for(category_id:, tag_names:)
    profiles.find do |profile|
      profile_applicable_for_values?(profile, category_id: category_id, tag_names: tag_names)
    end
  end

  def self.topic_applicable_for_profile?(topic, profile)
    category_id = topic.category_id if topic.respond_to?(:category_id)

    profile_applicable_for_values?(
      profile,
      category_id: category_id,
      tag_names: topic_tag_names(topic),
    )
  end

  def self.topic_applicable_profile(topic)
    applicable_profile_for(category_id: topic.category_id, tag_names: topic_tag_names(topic))
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

  def self.author_locked_field(profile)
    field_name(profile, "author_approval_locked")
  end

  def self.author_locked_by_id_field(profile)
    field_name(profile, "author_approval_locked_by_id")
  end

  def self.author_locked_at_field(profile)
    field_name(profile, "author_approval_locked_at")
  end

  def self.author_lock_post_id_field(profile)
    field_name(profile, "author_approval_lock_post_id")
  end

  def self.approved_action_code(profile)
    field_name(profile, "approved")
  end

  def self.unapproved_action_code(profile)
    field_name(profile, "unapproved")
  end

  def self.author_locked_action_code(profile)
    field_name(profile, "author_locked")
  end

  def self.author_unlocked_action_code(profile)
    field_name(profile, "author_unlocked")
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

  def self.topic_author_locked_for_profile?(topic, profile)
    value = topic_custom_field(topic, author_locked_field(profile))
    value == true || value == "true" || value == "t" || value == "1"
  end

  def self.topic_author_locked_by_id_for_profile(topic, profile)
    topic_custom_field(topic, author_locked_by_id_field(profile))
  end

  def self.topic_author_locked_at_for_profile(topic, profile)
    topic_custom_field(topic, author_locked_at_field(profile))
  end

  def self.status_token_valid?(token)
    configured_token = SiteSetting.tz_approval_status_token.to_s
    provided_token = token.to_s

    return false if configured_token.blank? || provided_token.blank?

    configured_digest = Digest::SHA256.hexdigest(configured_token)
    provided_digest = Digest::SHA256.hexdigest(provided_token)

    ActiveSupport::SecurityUtils.secure_compare(configured_digest, provided_digest)
  end

  def self.topic_status_payload(topic)
    approvals = approval_profiles_status(topic)
    tz_approval = approvals.find { |approval| approval[:profile_prefix] == DEFAULT_PROFILE_PREFIX }
    ss_approval = approvals.find do |approval|
      approval[:profile_prefix] == SS_PROFILE_PREFIX || approval[:profile_key] == SS_PROFILE_PREFIX
    end
    ss_approval ||= approvals.find do |approval|
      approval[:profile_prefix] == SECOND_LINE_PROFILE_PREFIX ||
        approval[:profile_key] == SECOND_LINE_PROFILE_PREFIX
    end
    solution = solution_status(topic)

    {
      ok: true,
      found: true,
      topic_id: topic.id,
      is_tz: tz_approval&.dig(:is_applicable) || false,
      tz_approved: tz_approval&.dig(:approved) || false,
      tz_approved_by: approved_by_payload(tz_approval),
      ss_approved: ss_approval&.dig(:approved) || false,
      ss_approved_by: approved_by_payload(ss_approval),
      approvals: approvals,
      can_set_solution: solution[:can_set_solution],
      has_solution: solution[:has_solution],
      solution: solution[:solution],
    }
  end

  def self.not_found_status_payload(topic_id: nil)
    {
      ok: true,
      found: false,
      topic_id: topic_id,
      approvals: [],
    }
  end

  def self.approval_profiles_status(topic)
    profiles.map do |profile|
      approved_by_id = topic_approved_by_id_for_profile(topic, profile)
      approved_user = User.find_by(id: approved_by_id)

      {
        profile_key: profile.key,
        profile_prefix: profile.prefix,
        profile_label: profile.label,
        priority: profile.priority,
        binding_mode: profile.binding_mode,
        is_applicable: topic_applicable_for_profile?(topic, profile),
        approved: topic_approved_for_profile?(topic, profile),
        author_approval_locked: topic_author_locked_for_profile?(topic, profile),
        approved_by: {
          id: approved_user&.id,
          username: approved_user&.username,
          at: topic_approved_at_for_profile(topic, profile),
        },
      }
    end
  end

  def self.approved_by_payload(approval)
    approved_by = approval&.dig(:approved_by) || {}

    {
      id: approved_by[:id],
      username: approved_by[:username],
      at: approved_by[:at],
    }
  end

  def self.solution_status(topic)
    solved_row = solved_topic_row(topic)
    answer_post_id = solved_row&.dig("answer_post_id")
    has_solution = answer_post_id.present?
    solution_post = has_solution ? Post.find_by(id: answer_post_id) : nil
    solution_marker = User.find_by(id: solved_row["accepter_user_id"]) if solved_row
    solution_author = User.find_by(id: solution_post.user_id) if solution_post

    {
      can_set_solution: category_solved_enabled?(topic) && (has_solution || topic_has_reply?(topic)),
      has_solution: has_solution,
      solution: {
        post_id: answer_post_id,
        marked_at: solved_row&.dig("created_at"),
        marked_by: {
          id: solution_marker&.id,
          username: solution_marker&.username,
        },
        post_author: {
          id: solution_author&.id,
          username: solution_author&.username,
        },
      },
    }
  end

  def self.solved_topic_row(topic)
    return nil unless ActiveRecord::Base.connection.data_source_exists?(SOLVED_TABLE_NAME)

    sql =
      ActiveRecord::Base.sanitize_sql_array(
        [
          <<~SQL,
            SELECT answer_post_id, accepter_user_id, created_at
            FROM #{SOLVED_TABLE_NAME}
            WHERE topic_id = ?
            LIMIT 1
          SQL
          topic.id.to_i,
        ],
      )

    ActiveRecord::Base.connection
      .exec_query(sql)
      .first
  rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
    nil
  end

  def self.category_solved_enabled?(topic)
    value =
      CategoryCustomField.find_by(
        category_id: topic.category_id,
        name: "enable_accepted_answers",
      )&.value

    value == true || value == "true" || value == "t" || value == "1"
  end

  def self.topic_has_reply?(topic)
    Post.where(topic_id: topic.id, deleted_at: nil).where("post_number > 1").exists?
  end

  def self.profile_payload(
    topic,
    guardian = nil,
    include_username: true,
    include_lock: false,
    redact_author_identity: false
  )
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
      approved_by_author: false,
      approved_by_id: nil,
      approved_by_username: nil,
      approved_at: nil,
    }

    if include_lock
      payload.merge!(
        author_approval_locked: false,
        author_approval_locked_by_id: nil,
        author_approval_locked_at: nil,
      )
    end

    if profile
      approved = topic_approved_for_profile?(topic, profile)
      approved_by_id = topic_approved_by_id_for_profile(topic, profile)
      approved_by_topic_author =
        approved_by_id.present? && approved_by_id.to_i == topic.user_id
      approved_by_author = approved && approved_by_topic_author
      visible_approved_by_id =
        redact_author_identity && approved_by_topic_author ? nil : approved_by_id
      locked_by_id = topic_author_locked_by_id_for_profile(topic, profile) if include_lock
      payload.merge!(
        approval_profile_key: profile.key,
        approval_profile_prefix: profile.prefix,
        approval_label: profile.label,
        approval_icon: profile.icon,
        approval_approve_text: profile.approve_text,
        approval_unapprove_text: profile.unapprove_text,
        approval_approved_text: profile.approved_text,
        approval_approved_by_author_text: profile.approved_by_author_text,
        approved: approved,
        approved_by_author: approved_by_author,
        approved_by_id: visible_approved_by_id,
        approved_at: topic_approved_at_for_profile(topic, profile),
      )

      if include_lock
        payload.merge!(
          author_approval_locked: topic_author_locked_for_profile?(topic, profile),
          author_approval_locked_by_id: locked_by_id,
          author_approval_locked_at: topic_author_locked_at_for_profile(topic, profile),
        )
      end

      if include_username && visible_approved_by_id.present?
        payload[:approved_by_username] = User.find_by(id: visible_approved_by_id)&.username
      end

      if include_lock && include_username && locked_by_id.present?
        payload[:author_approval_locked_by_username] = User.find_by(id: locked_by_id)&.username
      end
    end

    if guardian
      payload[:can_approve] = guardian.can_approve_tz?(topic)
      payload[:can_unapprove] = guardian.can_unapprove_tz?(topic)
      if include_lock
        payload[:can_lock_author_approval] = guardian.can_lock_tz_author_approval?(topic)
        payload[:can_unlock_author_approval] = guardian.can_unlock_tz_author_approval?(topic)
      end
    end

    payload
  end

  def self.tz_payload(topic, redact_author_identity: false)
    profile = all_profile_for_key(DEFAULT_PROFILE_KEY) || legacy_default_profile
    approved = topic_approved_for_profile?(topic, profile)
    approved_by_id = topic_approved_by_id_for_profile(topic, profile)
    approved_by_topic_author =
      approved_by_id.present? && approved_by_id.to_i == topic.user_id
    visible_approved_by_id =
      redact_author_identity && approved_by_topic_author ? nil : approved_by_id

    {
      tz_approved: approved,
      tz_approved_by_id: visible_approved_by_id,
      tz_approved_at: topic_approved_at_for_profile(topic, profile),
      tz_approved_by_username:
        visible_approved_by_id.present? ? User.find_by(id: visible_approved_by_id)&.username : nil,
    }
  end

  def self.topic_view_profile_payload(topic, guardian)
    profile_payload(
      topic,
      guardian,
      include_username: true,
      include_lock: true,
      redact_author_identity: true,
    )
  end

  def self.topic_list_profile_payload(topic)
    profile_payload(topic, nil, include_username: false, redact_author_identity: true)
  end

  def self.topic_view_tz_payload(topic)
    tz_payload(topic, redact_author_identity: true)
  end
end

require_relative "app/models/tz_approval/profile_record"

after_initialize do
  require_relative "app/controllers/tz_approval/approvals_controller"
  require_relative "app/controllers/tz_approval/status_controller"
  require_relative "app/controllers/tz_approval/admin/profiles_controller"
  require_relative "app/services/tz_approval/task_guid_requirement"

  existing_notification_type =
    Notification.types.find do |name, id|
      id == TzApproval::NOTIFICATION_TYPE_ID && name.to_s != "tz_approval"
    end

  if existing_notification_type
    Rails.logger.error(
      "tz-approval: notification type id #{TzApproval::NOTIFICATION_TYPE_ID} уже занят #{existing_notification_type.first}",
    )
  end

  Notification.types[:tz_approval] = TzApproval::NOTIFICATION_TYPE_ID
  TzApproval.ensure_default_profile_safely!

  # ── Требование связи с задачей ───────────────────────────────────────────────
  on(:after_validate_topic) do |topic, topic_creator|
    next if topic.errors.present?
    next if topic.private_message?
    next if topic_creator.opts[:skip_validations]

    allowed =
      TzApproval::TaskGuidRequirement.creation_allowed?(
        user: topic_creator.user,
        category_id: topic.category_id,
        tag_inputs: topic_creator.opts[:tags],
        opts: topic_creator.opts,
      )

    topic.errors.add(:base, TzApproval::TaskGuidRequirement.error_message) unless allowed
  end

  module TzApproval::PostRevisorTaskGuidExtensions
    def revise!(editor, fields, opts = {})
      normalized_fields = fields.with_indifferent_access
      category_changes =
        normalized_fields.key?(:category_id) &&
          normalized_fields[:category_id].to_i != @topic.category_id.to_i
      skip_validations = opts[:skip_validations] || opts["skip_validations"]

      return super unless category_changes

      tag_inputs =
        if normalized_fields.key?(:tags)
          normalized_fields[:tags]
        else
          TzApproval.topic_tag_names(@topic)
        end

      if skip_validations
        return TzApproval::TaskGuidRequirement.with_revision_context(
          @topic,
          user: editor,
          tag_inputs: tag_inputs,
          skip_validations: true,
        ) { super }
      end

      allowed =
        TzApproval::TaskGuidRequirement.category_change_allowed?(
          topic: @topic,
          user: editor,
          category_id: normalized_fields[:category_id],
          tag_inputs: tag_inputs,
        )

      unless allowed
        message = TzApproval::TaskGuidRequirement.error_message
        @post.errors.add(:base, message)
        @topic.errors.add(:base, message)
        return false
      end

      TzApproval::TaskGuidRequirement.with_revision_context(
        @topic,
        user: editor,
        tag_inputs: tag_inputs,
        skip_validations: false,
      ) { super }
    end
  end

  module TzApproval::TopicTaskGuidExtensions
    def change_category_to_id(category_id, *args, **kwargs, &block)
      context = TzApproval::TaskGuidRequirement.revision_context(self) || {}
      return super if context[:skip_validations]

      user =
        context[:user] ||
          (acting_user if respond_to?(:acting_user)) ||
          TzApproval::TaskGuidRequirement.category_change_user
      tag_inputs =
        if context.key?(:tag_inputs)
          context[:tag_inputs]
        else
          TzApproval.topic_tag_names(self)
        end

      allowed =
        TzApproval::TaskGuidRequirement.category_change_allowed?(
          topic: self,
          user: user,
          category_id: category_id,
          tag_inputs: tag_inputs,
        )

      unless allowed
        errors.add(:base, TzApproval::TaskGuidRequirement.error_message)
        return false
      end

      super
    end
  end

  module TzApproval::TopicsBulkActionTaskGuidExtensions
    def perform!(*args, **kwargs, &block)
      operation_type =
        if @operation.respond_to?(:[])
          @operation[:type] || @operation["type"]
        end

      return super unless operation_type.to_s == "change_category"

      TzApproval::TaskGuidRequirement.with_category_change_user(@user) { super }
    end
  end

  reloadable_patch do
    ::PostRevisor.prepend(TzApproval::PostRevisorTaskGuidExtensions)
    ::Topic.prepend(TzApproval::TopicTaskGuidExtensions)
    if defined?(::TopicsBulkAction)
      ::TopicsBulkAction.prepend(TzApproval::TopicsBulkActionTaskGuidExtensions)
    end
  end

  # ── Custom fields ────────────────────────────────────────────────────────────
  TzApproval.all_profiles.each do |profile|
    register_topic_custom_field_type(TzApproval.approved_field(profile), :boolean)
    register_topic_custom_field_type(TzApproval.approved_by_id_field(profile), :integer)
    register_topic_custom_field_type(TzApproval.approved_at_field(profile), :string)
    register_topic_custom_field_type(TzApproval.approval_post_id_field(profile), :integer)
    register_topic_custom_field_type(TzApproval.author_locked_field(profile), :boolean)
    register_topic_custom_field_type(TzApproval.author_locked_by_id_field(profile), :integer)
    register_topic_custom_field_type(TzApproval.author_locked_at_field(profile), :string)
    register_topic_custom_field_type(TzApproval.author_lock_post_id_field(profile), :integer)

    add_preloaded_topic_list_custom_field(TzApproval.approved_field(profile))
    add_preloaded_topic_list_custom_field(TzApproval.approved_by_id_field(profile))
    add_preloaded_topic_list_custom_field(TzApproval.approved_at_field(profile))
  end

  TopicList.on_preload do |topics, _topic_list|
    approval_fields =
      TzApproval.profiles.flat_map do |profile|
        [
          TzApproval.approved_field(profile),
          TzApproval.approved_by_id_field(profile),
          TzApproval.approved_at_field(profile),
        ]
      end.uniq

    existing_fields =
      topics.flat_map do |topic|
        topic.preloaded_custom_fields&.keys || []
      end

    fields = (existing_fields + approval_fields).uniq

    Topic.preload_custom_fields(topics, fields) if topics.present? && fields.present?
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
      if @user&.id == topic.user_id && TzApproval.topic_author_locked_for_profile?(topic, profile)
        return false
      end
      return true if is_staff?

      if @user&.id == topic.user_id
        delay = SiteSetting.tz_author_approval_delay.to_i
        return Time.now.to_i - topic.created_at.to_i >= delay
      end

      allowed = profile.allowed_groups.map(&:to_i)
      return true if allowed.present? && @user&.in_any_groups?(allowed)

      false
    end

    def ensure_can_approve_tz!(topic)
      raise Discourse::InvalidAccess.new unless can_approve_tz?(topic)
    end

    def can_unapprove_tz?(topic)
      profile = TzApproval.topic_applicable_profile(topic)
      return false unless profile
      return false unless TzApproval.topic_approved_for_profile?(topic, profile)
      if @user&.id == topic.user_id && TzApproval.topic_author_locked_for_profile?(topic, profile)
        return false
      end

      allowed = profile.allowed_groups.map(&:to_i)
      approved_by_id = TzApproval.topic_approved_by_id_for_profile(topic, profile)

      is_staff? ||
        (allowed.present? && @user&.in_any_groups?(allowed)) ||
        (@user&.id == topic.user_id && approved_by_id.to_i == @user&.id)
    end

    def ensure_can_unapprove_tz!(topic)
      raise Discourse::InvalidAccess.new unless can_unapprove_tz?(topic)
    end

    def can_manage_tz_author_approval_lock?(topic)
      profile = TzApproval.topic_applicable_profile(topic)
      return false unless profile
      return false unless @user
      return false if @user.id == topic.user_id
      return true if is_staff?

      allowed = profile.allowed_groups.map(&:to_i)
      allowed.present? && !!@user.in_any_groups?(allowed)
    end

    def can_lock_tz_author_approval?(topic)
      profile = TzApproval.topic_applicable_profile(topic)
      return false unless profile
      return false unless can_manage_tz_author_approval_lock?(topic)

      !TzApproval.topic_author_locked_for_profile?(topic, profile)
    end

    def can_unlock_tz_author_approval?(topic)
      profile = TzApproval.topic_applicable_profile(topic)
      return false unless profile
      return false unless can_manage_tz_author_approval_lock?(topic)

      TzApproval.topic_author_locked_for_profile?(topic, profile)
    end

    def ensure_can_lock_tz_author_approval!(topic)
      raise Discourse::InvalidAccess.new unless can_manage_tz_author_approval_lock?(topic)
    end

    def ensure_can_unlock_tz_author_approval!(topic)
      raise Discourse::InvalidAccess.new unless can_manage_tz_author_approval_lock?(topic)
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
      @tz_approval_payload ||= TzApproval.topic_view_profile_payload(object.topic, scope)
      @tz_approval_payload[field]
    end

    add_to_serializer(:topic_list_item, field) do
      @tz_approval_payload ||= TzApproval.topic_list_profile_payload(object)
      @tz_approval_payload[field]
    end
  end

  add_to_serializer(:topic_view, :approved_by_author) do
    @tz_approval_payload ||= TzApproval.topic_view_profile_payload(object.topic, scope)
    @tz_approval_payload[:approved_by_author]
  end

  add_to_serializer(:topic_view, :approved_by_username) do
    @tz_approval_payload ||= TzApproval.topic_view_profile_payload(object.topic, scope)
    @tz_approval_payload[:approved_by_username]
  end

  add_to_serializer(:topic_view, :can_approve) do
    @tz_approval_payload ||= TzApproval.topic_view_profile_payload(object.topic, scope)
    @tz_approval_payload[:can_approve]
  end

  add_to_serializer(:topic_view, :can_unapprove) do
    @tz_approval_payload ||= TzApproval.topic_view_profile_payload(object.topic, scope)
    @tz_approval_payload[:can_unapprove]
  end

  %i[
    author_approval_locked
    author_approval_locked_by_id
    author_approval_locked_by_username
    author_approval_locked_at
    can_lock_author_approval
    can_unlock_author_approval
  ].each do |field|
    add_to_serializer(:topic_view, field) do
      @tz_approval_payload ||= TzApproval.topic_view_profile_payload(object.topic, scope)
      @tz_approval_payload[field]
    end
  end

  add_to_serializer(:topic_view, :tz_approved) do
    @tz_approval_legacy_payload ||= TzApproval.topic_view_tz_payload(object.topic)
    @tz_approval_legacy_payload[:tz_approved]
  end

  add_to_serializer(:topic_view, :tz_approved_by_id) do
    @tz_approval_legacy_payload ||= TzApproval.topic_view_tz_payload(object.topic)
    @tz_approval_legacy_payload[:tz_approved_by_id]
  end

  add_to_serializer(:topic_view, :tz_approved_at) do
    @tz_approval_legacy_payload ||= TzApproval.topic_view_tz_payload(object.topic)
    @tz_approval_legacy_payload[:tz_approved_at]
  end

  add_to_serializer(:topic_view, :tz_approved_by_username) do
    @tz_approval_legacy_payload ||= TzApproval.topic_view_tz_payload(object.topic)
    @tz_approval_legacy_payload[:tz_approved_by_username]
  end

  add_to_serializer(:topic_view, :can_approve_tz) do
    @tz_approval_payload ||= TzApproval.topic_view_profile_payload(object.topic, scope)
    @tz_approval_payload[:can_approve]
  end

  add_to_serializer(:topic_view, :can_unapprove_tz) do
    @tz_approval_payload ||= TzApproval.topic_view_profile_payload(object.topic, scope)
    @tz_approval_payload[:can_unapprove]
  end

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
    return posts.none unless profile&.prefix.to_s.match?(TzApproval::PROFILE_PREFIX_REGEXP)

    approval_cf_alias = "tz_approval_#{profile.prefix}_approved_cf"
    approved_field = ActiveRecord::Base.connection.quote(TzApproval.approved_field(profile))

    profile_applicable_search_filter
      .call(posts, profile)
      .joins(<<~SQL)
        INNER JOIN topic_custom_fields #{approval_cf_alias}
          ON #{approval_cf_alias}.topic_id = topics.id
         AND #{approval_cf_alias}.name = #{approved_field}
         AND #{approval_cf_alias}.value IN ('t', 'true', '1')
      SQL
  end

  profile_unapproved_search_filter = lambda do |posts, profile|
    return posts.none unless profile&.prefix.to_s.match?(TzApproval::PROFILE_PREFIX_REGEXP)

    approval_cf_alias = "tz_approval_#{profile.prefix}_approved_cf"
    approved_field = ActiveRecord::Base.connection.quote(TzApproval.approved_field(profile))

    profile_applicable_search_filter
      .call(posts, profile)
      .where(<<~SQL)
        NOT EXISTS (
          SELECT 1
          FROM topic_custom_fields #{approval_cf_alias}
          WHERE #{approval_cf_alias}.topic_id = topics.id
            AND #{approval_cf_alias}.name = #{approved_field}
            AND #{approval_cf_alias}.value IN ('t', 'true', '1')
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
    post "/tz-approval/lock-author-approval" => "tz_approval/approvals#lock_author_approval"
    post "/tz-approval/unlock-author-approval" => "tz_approval/approvals#unlock_author_approval"
    get "/approvals/topic-id/:id/:token" => "tz_approval/status#show_by_topic_id",
        defaults: { format: :json }
    get "/approvals/topic-id/:id" => "tz_approval/status#show_by_topic_id",
        defaults: { format: :json }

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
