# frozen_string_literal: true

module TzApproval
  module Admin
    class ProfilesController < ::ApplicationController
      requires_plugin TzApproval::PLUGIN_NAME

      before_action :ensure_site_admin
      before_action :find_profile, only: %i[update destroy]

      def index
        TzApproval.ensure_default_profile!

        render json: {
          profiles: TzApproval::ProfileRecord.ordered.map(&:as_json),
          categories: category_options,
          groups: group_options,
          tags: tag_options,
        }
      end

      def create
        profile = TzApproval::ProfileRecord.new(profile_params)
        profile.save!

        render json: { profile: profile.as_json }
      rescue ActiveRecord::RecordInvalid => e
        render_json_error(e.record.errors.full_messages.join(", "), status: 422)
      end

      def update
        update_params = profile_params
        update_params.delete(:key)
        update_params.delete(:prefix)

        @profile.update!(update_params)

        render json: { profile: @profile.as_json }
      rescue ActiveRecord::RecordInvalid => e
        render_json_error(e.record.errors.full_messages.join(", "), status: 422)
      end

      def destroy
        if @profile.system?
          render_json_error(I18n.t("tz_approval.admin.errors.default_profile_delete"), status: 422)
          return
        end

        @profile.destroy!
        render json: success_json
      end

      private

      def ensure_site_admin
        if guardian.respond_to?(:ensure_can_admin_site!)
          guardian.ensure_can_admin_site!
        elsif !current_user&.admin?
          raise Discourse::InvalidAccess.new
        end
      end

      def find_profile
        @profile = TzApproval::ProfileRecord.find(params[:id])
      end

      def profile_params
        params
          .require(:profile)
          .permit(
            :key,
            :prefix,
            :label,
            :enabled,
            :priority,
            :binding_mode,
            :require_task_guid,
            :icon,
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
            category_ids: [],
            allowed_group_ids: [],
            tags: [],
          )
      end

      def category_options
        Category
          .order(:position, :name)
          .pluck(:id, :name)
          .map { |id, name| { id: id, name: name } }
      end

      def group_options
        Group
          .order(:name)
          .pluck(:id, :name)
          .map { |id, name| { id: id, name: name } }
      end

      def tag_options
        Tag.order(:name).pluck(:name)
      end
    end
  end
end
