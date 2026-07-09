# frozen_string_literal: true

module TzApproval
  class StatusController < ::ApplicationController
    requires_plugin TzApproval::PLUGIN_NAME

    before_action :ensure_valid_status_token

    def show_by_topic_id
      topic_id = params[:id].to_i
      topic = Topic.find_by(id: topic_id)

      if topic
        render json: TzApproval.topic_status_payload(topic)
      else
        render json: TzApproval.not_found_status_payload(topic_id: topic_id)
      end
    end

    private

    def ensure_valid_status_token
      return if TzApproval.status_token_valid?(provided_status_token)

      RateLimiter.new(nil, "tz-approval-status-#{request.remote_ip}", 20, 1.minute).performed!

      render json: { ok: false, error: "invalid_token" }, status: 403
    end

    def provided_status_token
      request.headers["X-TZ-Approval-Token"].presence || params[:token].presence
    end
  end
end
