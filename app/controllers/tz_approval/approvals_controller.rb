# frozen_string_literal: true

module TzApproval
  class ApprovalsController < ::ApplicationController
    requires_plugin TzApproval::PLUGIN_NAME
    before_action :ensure_logged_in

    def approve
      topic = Topic.find(params[:topic_id])
      profile = TzApproval.topic_applicable_profile(topic)

      raise Discourse::InvalidAccess.new unless profile
      guardian.ensure_can_approve_tz!(topic)

      approved_topic = nil
      create_approval_event = false

      ActiveRecord::Base.transaction do
        topic = Topic.lock.find(topic.id)
        profile = TzApproval.topic_applicable_profile(topic)

        raise Discourse::InvalidAccess.new unless profile

        if TzApproval.topic_approved_for_profile?(topic, profile)
          approved_topic = topic
          next
        end

        approved_at = Time.now.utc
        topic.custom_fields[TzApproval.approved_field(profile)] = true
        topic.custom_fields[TzApproval.approved_by_id_field(profile)] = current_user.id
        topic.custom_fields[TzApproval.approved_at_field(profile)] = approved_at.iso8601
        topic.save_custom_fields(true)

        approved_topic = topic
        create_approval_event = true
      end

      if create_approval_event
        post =
          create_tz_approval_status_post(
            approved_topic,
            profile,
            profile.approved_action_text,
            TzApproval.approved_action_code(profile),
          )

        approved_topic.custom_fields[TzApproval.approval_post_id_field(profile)] = post.id
        approved_topic.save_custom_fields(true)
        notify_topic_author(approved_topic, profile, post, "approved")
      end

      set_current_user_to_watching(approved_topic)

      MessageBus.publish("/topic/#{approved_topic.id}", reload_topic: true, refresh_stream: true)
      render json: success_json.merge(tz_approval_payload(approved_topic))
    end

    def unapprove
      topic = Topic.find(params[:topic_id])
      profile = TzApproval.topic_applicable_profile(topic)

      raise Discourse::InvalidAccess.new unless profile
      guardian.ensure_can_unapprove_tz!(topic)

      unapproved_topic = nil
      create_unapproval_event = false

      ActiveRecord::Base.transaction do
        topic = Topic.lock.find(topic.id)
        profile = TzApproval.topic_applicable_profile(topic)

        raise Discourse::InvalidAccess.new unless profile

        unless TzApproval.topic_approved_for_profile?(topic, profile)
          unapproved_topic = topic
          next
        end

        topic.custom_fields[TzApproval.approved_field(profile)] = nil
        topic.custom_fields[TzApproval.approved_by_id_field(profile)] = nil
        topic.custom_fields[TzApproval.approved_at_field(profile)] = nil
        topic.custom_fields[TzApproval.approval_post_id_field(profile)] = nil
        topic.save_custom_fields(true)

        unapproved_topic = topic
        create_unapproval_event = true
      end

      if create_unapproval_event
        post =
          create_tz_approval_status_post(
            unapproved_topic,
            profile,
            profile.unapproved_action_text,
            TzApproval.unapproved_action_code(profile),
          )

        notify_topic_author(unapproved_topic, profile, post, "unapproved")
      end

      MessageBus.publish("/topic/#{unapproved_topic.id}", reload_topic: true, refresh_stream: true)
      render json: success_json.merge(tz_approval_payload(unapproved_topic))
    end

    def lock_author_approval
      topic = Topic.find(params[:topic_id])
      profile = TzApproval.topic_applicable_profile(topic)

      raise Discourse::InvalidAccess.new unless profile
      guardian.ensure_can_lock_tz_author_approval!(topic)

      locked_topic = nil
      create_lock_event = false

      ActiveRecord::Base.transaction do
        topic = Topic.lock.find(topic.id)
        profile = TzApproval.topic_applicable_profile(topic)

        raise Discourse::InvalidAccess.new unless profile

        if TzApproval.topic_author_locked_for_profile?(topic, profile)
          locked_topic = topic
          next
        end

        locked_at = Time.now.utc
        topic.custom_fields[TzApproval.author_locked_field(profile)] = true
        topic.custom_fields[TzApproval.author_locked_by_id_field(profile)] = current_user.id
        topic.custom_fields[TzApproval.author_locked_at_field(profile)] = locked_at.iso8601
        topic.save_custom_fields(true)

        locked_topic = topic
        create_lock_event = true
      end

      if create_lock_event
        post =
          create_tz_approval_status_post(
            locked_topic,
            profile,
            profile.author_locked_action_text,
            TzApproval.author_locked_action_code(profile),
          )

        locked_topic.custom_fields[TzApproval.author_lock_post_id_field(profile)] = post.id
        locked_topic.save_custom_fields(true)
        notify_topic_author(locked_topic, profile, post, "author_locked")
      end

      MessageBus.publish("/topic/#{locked_topic.id}", reload_topic: true, refresh_stream: true)
      render json: success_json.merge(tz_approval_payload(locked_topic))
    end

    def unlock_author_approval
      topic = Topic.find(params[:topic_id])
      profile = TzApproval.topic_applicable_profile(topic)

      raise Discourse::InvalidAccess.new unless profile
      guardian.ensure_can_unlock_tz_author_approval!(topic)

      unlocked_topic = nil
      create_unlock_event = false

      ActiveRecord::Base.transaction do
        topic = Topic.lock.find(topic.id)
        profile = TzApproval.topic_applicable_profile(topic)

        raise Discourse::InvalidAccess.new unless profile

        unless TzApproval.topic_author_locked_for_profile?(topic, profile)
          unlocked_topic = topic
          next
        end

        topic.custom_fields[TzApproval.author_locked_field(profile)] = nil
        topic.custom_fields[TzApproval.author_locked_by_id_field(profile)] = nil
        topic.custom_fields[TzApproval.author_locked_at_field(profile)] = nil
        topic.custom_fields[TzApproval.author_lock_post_id_field(profile)] = nil
        topic.save_custom_fields(true)

        unlocked_topic = topic
        create_unlock_event = true
      end

      if create_unlock_event
        post =
          create_tz_approval_status_post(
            unlocked_topic,
            profile,
            profile.author_unlocked_action_text,
            TzApproval.author_unlocked_action_code(profile),
          )

        notify_topic_author(unlocked_topic, profile, post, "author_unlocked")
      end

      MessageBus.publish("/topic/#{unlocked_topic.id}", reload_topic: true, refresh_stream: true)
      render json: success_json.merge(tz_approval_payload(unlocked_topic))
    end

    private

    def set_current_user_to_watching(topic)
      TopicUser.change(
        current_user,
        topic.id,
        notification_level: TopicUser.notification_levels[:watching],
      )
    end

    def create_tz_approval_status_post(topic, profile, raw_template, action_code)
      PostCreator.create!(
        Discourse.system_user,
        raw: format_profile_text(raw_template, topic, profile),
        topic_id: topic.id,
        post_type: Post.types[:small_action],
        action_code: action_code,
        skip_validations: true,
        bypass_bump: true,
        skip_jobs: true,
      )
    end

    def notify_topic_author(topic, profile, post, action)
      return if current_user.id == topic.user_id

      topic_author = User.find_by(id: topic.user_id)
      return if topic_author.blank?

      screener =
        UserCommScreener.new(acting_user_id: current_user.id, target_user_ids: topic_author.id)
      return if screener.ignoring_or_muting_actor?(topic_author.id)

      Notification.create!(
        notification_type: Notification.types[:tz_approval],
        user_id: topic_author.id,
        topic_id: topic.id,
        post_number: post.post_number,
        data: {
          action: action,
          profile_key: profile.key,
          profile_prefix: profile.prefix,
          profile_label: profile.label,
          description: notification_description(profile, action),
          message: notification_description(profile, action),
          title: "tz_approval.notification.title",
          display_username: current_user.username,
          topic_title: topic.title,
        }.to_json,
      )
    end

    def notification_description(profile, action)
      case action
      when "unapproved"
        profile.unapproved_description
      when "author_locked"
        I18n.t("tz_approval.notification.author_locked_description", label: profile.label.to_s)
      when "author_unlocked"
        I18n.t("tz_approval.notification.author_unlocked_description", label: profile.label.to_s)
      else
        profile.approved_description
      end
    end

    def format_profile_text(template, topic, profile)
      template.to_s
        .gsub("%{username}", tz_approval_actor(topic))
        .gsub("%{label}", profile.label.to_s)
    end

    def tz_approval_actor(topic)
      if current_user.id == topic.user_id
        I18n.t("tz_approval.topic_author")
      else
        "@#{current_user.username}"
      end
    end

    def tz_approval_payload(topic)
      TzApproval
        .profile_payload(topic, guardian, include_username: true, include_lock: true)
        .merge(TzApproval.tz_payload(topic))
        .merge(
          can_approve_tz: guardian.can_approve_tz?(topic),
          can_unapprove_tz: guardian.can_unapprove_tz?(topic),
        )
    end
  end
end
