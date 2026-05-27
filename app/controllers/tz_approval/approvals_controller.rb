# frozen_string_literal: true

module TzApproval
  class ApprovalsController < ::ApplicationController
    requires_plugin TzApproval::PLUGIN_NAME
    before_action :ensure_logged_in

    def approve
      topic = Topic.find(params[:topic_id])

      raise Discourse::InvalidAccess.new unless TzApproval.topic_applicable?(topic)
      guardian.ensure_can_approve_tz!(topic)

      approved_topic = nil

      ActiveRecord::Base.transaction do
        topic = Topic.lock.find(topic.id)

        if topic.tz_approved?
          approved_topic = topic
          next
        end

        approved_at = Time.now.utc
        topic.custom_fields["tz_approved"]       = true
        topic.custom_fields["tz_approved_by_id"] = current_user.id
        topic.custom_fields["tz_approved_at"]    = approved_at.iso8601

        post = create_tz_approval_status_post(topic, "approved_action", "tz_approved")
        topic.custom_fields["tz_approval_post_id"] = post.id
        topic.save_custom_fields(true)
        notify_topic_author(topic, post, "approved")

        approved_topic = topic
      end

      set_current_user_to_watching(approved_topic)

      MessageBus.publish("/topic/#{approved_topic.id}", reload_topic: true, refresh_stream: true)
      render json: success_json.merge(tz_approval_payload(approved_topic))
    end

    def unapprove
      topic = Topic.find(params[:topic_id])
      guardian.ensure_can_unapprove_tz!(topic)

      unapproved_topic = nil

      ActiveRecord::Base.transaction do
        topic = Topic.lock.find(topic.id)

        unless topic.tz_approved?
          unapproved_topic = topic
          next
        end

        topic.custom_fields["tz_approved"]         = nil
        topic.custom_fields["tz_approved_by_id"]   = nil
        topic.custom_fields["tz_approved_at"]       = nil
        topic.custom_fields["tz_approval_post_id"] = nil
        topic.save_custom_fields(true)
        post = create_tz_approval_status_post(topic, "unapproved_action", "tz_unapproved")
        notify_topic_author(topic, post, "unapproved")

        unapproved_topic = topic
      end

      MessageBus.publish("/topic/#{unapproved_topic.id}", reload_topic: true, refresh_stream: true)
      render json: success_json.merge(tz_approval_payload(unapproved_topic))
    end

    private

    def set_current_user_to_watching(topic)
      TopicUser.change(
        current_user,
        topic.id,
        notification_level: TopicUser.notification_levels[:watching],
      )
    end

    def create_tz_approval_status_post(topic, translation_key, action_code)
      PostCreator.create!(
        Discourse.system_user,
        raw:              I18n.t(
          "tz_approval.#{translation_key}",
          username: tz_approval_actor(topic),
        ),
        topic_id:         topic.id,
        post_type:        Post.types[:small_action],
        action_code:      action_code,
        skip_validations: true,
        bypass_bump:      true,
        skip_jobs:        true,
      )
    end

    def notify_topic_author(topic, post, action)
      return if current_user.id == topic.user_id

      topic_author = User.find_by(id: topic.user_id)
      return if topic_author.blank?

      screener =
        UserCommScreener.new(acting_user_id: current_user.id, target_user_ids: topic_author.id)
      return if screener.ignoring_or_muting_actor?(topic_author.id)

      Notification.create!(
        notification_type: Notification.types[:tz_approval],
        user_id:           topic_author.id,
        topic_id:          topic.id,
        post_number:       post.post_number,
        data:              {
          action:           action,
          message:          "tz_approval.notification.#{action}_notification",
          title:            "tz_approval.notification.title",
          display_username: current_user.username,
          topic_title:      topic.title,
        }.to_json,
      )
    end

    def tz_approval_actor(topic)
      if current_user.id == topic.user_id
        I18n.t("tz_approval.topic_author")
      else
        "@#{current_user.username}"
      end
    end

    def tz_approval_payload(topic)
      {
        tz_approved:             topic.tz_approved?,
        tz_approved_by_id:       topic.tz_approved_by_id,
        tz_approved_at:          topic.tz_approved_at,
        tz_approved_by_username: User.find_by(id: topic.tz_approved_by_id)&.username,
        can_approve_tz:          guardian.can_approve_tz?(topic),
        can_unapprove_tz:        guardian.can_unapprove_tz?(topic),
      }
    end
  end
end
