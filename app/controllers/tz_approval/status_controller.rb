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

    def show_by_guid
      guid = params[:guid].to_s.strip
      topic = TzApproval.topic_for_guid(guid)

      if topic
        render json: TzApproval.topic_status_payload(topic)
      else
        render json: TzApproval.not_found_status_payload(guid: guid)
      end
    end

    private

    def ensure_valid_status_token
      return if TzApproval.status_token_valid?(params[:token])

      render json: { ok: false, error: "invalid_token" }, status: 403
    end
  end
end
