# frozen_string_literal: true

module TzApproval
  class ApprovalsController < ::ApplicationController
    requires_plugin TzApproval::PLUGIN_NAME
    before_action :ensure_logged_in

    def approve
      topic = Topic.find(params[:topic_id])

      raise Discourse::InvalidAccess.new unless TzApproval.topic_applicable?(topic)
      guardian.ensure_can_approve_tz!(topic)

      ActiveRecord::Base.transaction do
        approved_at = Time.now.utc
        topic.custom_fields["tz_approved"]       = true
        topic.custom_fields["tz_approved_by_id"] = current_user.id
        topic.custom_fields["tz_approved_at"]    = approved_at.iso8601
        topic.save_custom_fields(true)
        create_tz_approval_status_post(topic, "approved_action", "tz_approved", approved_at)
      end

      MessageBus.publish("/topic/#{topic.id}", reload_topic: true, refresh_stream: true)
      render json: success_json.merge(tz_approval_payload(topic))
    end

    def unapprove
      topic = Topic.find(params[:topic_id])
      guardian.ensure_can_unapprove_tz!(topic)

      ActiveRecord::Base.transaction do
        post_id = topic.custom_fields["tz_approval_post_id"]
        if post_id.present?
          post = Post.find_by(id: post_id.to_i)
          PostDestroyer.new(current_user, post).destroy if post
        end

        topic.custom_fields["tz_approved"]         = nil
        topic.custom_fields["tz_approved_by_id"]   = nil
        topic.custom_fields["tz_approved_at"]       = nil
        topic.custom_fields["tz_approval_post_id"] = nil
        topic.save_custom_fields(true)
        create_tz_approval_status_post(topic, "unapproved_action", "tz_unapproved", Time.now.utc)
      end

      MessageBus.publish("/topic/#{topic.id}", reload_topic: true, refresh_stream: true)
      render json: success_json.merge(tz_approval_payload(topic))
    end

    private

    def create_tz_approval_status_post(topic, translation_key, action_code, acted_at)
      PostCreator.create!(
        Discourse.system_user,
        raw:              I18n.t(
          "tz_approval.#{translation_key}",
          username: tz_approval_actor(topic),
          time: format_tz_approval_time(acted_at),
        ),
        topic_id:         topic.id,
        post_type:        Post.types[:small_action],
        action_code:      action_code,
        skip_validations: true,
        bypass_bump:      true,
      )
    end

    def tz_approval_actor(topic)
      if current_user.id == topic.user_id
        I18n.t("tz_approval.topic_author")
      else
        "@#{current_user.username}"
      end
    end

    def format_tz_approval_time(time)
      time.utc.strftime("%Y-%m-%d %H:%M UTC")
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
