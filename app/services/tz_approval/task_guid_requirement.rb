# frozen_string_literal: true

module TzApproval
  class TaskGuidRequirement
    ERROR_KEY = "tz_approval.errors.task_guid_required"
    CATEGORY_CHANGE_USER_KEY = :tz_approval_category_change_user
    REVISION_CONTEXT_IVAR = :@tz_approval_task_guid_revision_context

    class << self
      def creation_allowed?(user:, category_id:, tag_inputs:, opts:)
        profile = protected_profile(category_id:, tag_inputs:)
        return true unless profile
        return true if user&.admin?

        plugin = guid_plugin
        return false unless contract_available?(plugin)

        guid = plugin.normalize_guid(option(opts, :task_guid))
        return false if guid.blank?
        return false unless plugin.valid_create_signature?(guid, opts)

        plugin.topic_for_guid(guid).nil?
      rescue StandardError => e
        log_contract_error(e)
        false
      end

      def category_change_allowed?(topic:, user:, category_id:, tag_inputs:)
        profile = protected_profile(category_id:, tag_inputs:)
        return true unless profile
        return true if user&.admin?

        plugin = guid_plugin
        return false unless contract_available?(plugin)

        field_name = plugin.const_get(:FIELD_NAME, false)
        plugin.normalize_guid(TzApproval.topic_custom_field(topic, field_name)).present?
      rescue StandardError => e
        log_contract_error(e)
        false
      end

      def protected_profile(category_id:, tag_inputs:)
        profile =
          TzApproval.applicable_profile_for(
            category_id: category_id,
            tag_names: normalize_tag_names(tag_inputs),
          )

        return unless profile&.enabled
        return unless profile.binding_mode == TzApproval::CATEGORY_BINDING_MODE
        return unless profile.require_task_guid

        profile
      end

      def normalize_tag_names(tag_inputs)
        ids = []
        names = []

        Array(tag_inputs).each do |tag|
          if tag.respond_to?(:name)
            names << tag.name
          elsif tag.is_a?(Hash) || tag.respond_to?(:key?)
            id = tag[:id] || tag["id"]
            name = tag[:name] || tag["name"]
            if id.present?
              ids << id.to_i
            elsif name.present?
              names << name
            end
          elsif tag.is_a?(Integer)
            ids << tag
          else
            names << tag
          end
        end

        names.concat(Tag.where(id: ids.uniq).pluck(:name)) if ids.present?
        names.map(&:to_s).map(&:strip).reject(&:blank?).uniq
      end

      def with_category_change_user(user)
        previous = RequestStore.store[CATEGORY_CHANGE_USER_KEY]
        RequestStore.store[CATEGORY_CHANGE_USER_KEY] = user
        yield
      ensure
        RequestStore.store[CATEGORY_CHANGE_USER_KEY] = previous
      end

      def category_change_user
        RequestStore.store[CATEGORY_CHANGE_USER_KEY]
      end

      def with_revision_context(topic, user:, tag_inputs:, skip_validations:)
        previous = topic.instance_variable_get(REVISION_CONTEXT_IVAR)
        topic.instance_variable_set(
          REVISION_CONTEXT_IVAR,
          {
            user: user,
            tag_inputs: tag_inputs,
            skip_validations: skip_validations,
          },
        )
        yield
      ensure
        topic.instance_variable_set(REVISION_CONTEXT_IVAR, previous)
      end

      def revision_context(topic)
        topic.instance_variable_get(REVISION_CONTEXT_IVAR)
      end

      def error_message
        I18n.t(ERROR_KEY)
      end

      private

      def guid_plugin
        ::DiscourseNewTopicField if defined?(::DiscourseNewTopicField)
      end

      def contract_available?(plugin)
        return false unless plugin
        return false unless guid_plugin_enabled?
        return false unless plugin.const_defined?(:FIELD_NAME, false)

        %i[normalize_guid valid_create_signature? topic_for_guid].all? do |method_name|
          plugin.respond_to?(method_name)
        end
      end

      def guid_plugin_enabled?
        SiteSetting.respond_to?(:discourse_new_topic_field_enabled) &&
          SiteSetting.discourse_new_topic_field_enabled
      end

      def option(opts, key)
        opts[key] || opts[key.to_s]
      end

      def log_contract_error(error)
        Rails.logger.warn(
          "tz-approval: не удалось проверить связь с задачей: #{error.class}: #{error.message}",
        )
      end
    end
  end
end
