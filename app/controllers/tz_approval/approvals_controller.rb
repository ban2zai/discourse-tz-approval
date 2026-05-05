# frozen_string_literal: true

module TzApproval
  class ApprovalsController < ::ApplicationController
    requires_plugin TzApproval::PLUGIN_NAME
    before_action :ensure_logged_in

    def approve
      topic = Topic.find(params[:topic_id])

      topic_tags    = topic.tags.pluck(:name)
      approval_tags = SiteSetting.tz_approval_tags.split("|").map(&:strip)
      raise Discourse::InvalidAccess.new if (topic_tags & approval_tags).empty?

      guardian.ensure_can_approve_tz!(topic)

      ActiveRecord::Base.transaction do
        topic.custom_fields["tz_approved"]       = true
        topic.custom_fields["tz_approved_by_id"] = current_user.id
        topic.custom_fields["tz_approved_at"]    = Time.now.utc.iso8601
        topic.save_custom_fields(true)

        post = PostCreator.create!(
          Discourse.system_user,
          raw:              I18n.t("tz_approval.approved_action", username: current_user.username),
          topic_id:         topic.id,
          post_type:        Post.types[:small_action],
          action_code:      "tz_approved",
          skip_validations: true,
          bypass_bump:      true,
          custom_fields:    { "tz_approval_post" => true },
        )

        topic.custom_fields["tz_approval_post_id"] = post.id
        topic.save_custom_fields(true)
      end

      MessageBus.publish("/topic/#{topic.id}", reload_topic: true, refresh_stream: true)
      render json: success_json
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
      end

      MessageBus.publish("/topic/#{topic.id}", reload_topic: true, refresh_stream: true)
      render json: success_json
    end
  end
end
