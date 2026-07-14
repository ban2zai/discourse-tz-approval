import Component from "@glimmer/component";
import { service } from "@ember/service";
import { apiInitializer } from "discourse/lib/api";
import dIcon from "discourse-common/helpers/d-icon";
import { i18n } from "discourse-i18n";

const DEFAULT_ICON = "file-signature";
const ICON_REGEXP = /^[a-z0-9-]+$/;

function safeIcon(icon) {
  return ICON_REGEXP.test(icon || "") ? icon : DEFAULT_ICON;
}

export default apiInitializer((api) => {
  api.renderInOutlet(
    "after-topic-status",
    class TzApprovalTopicStatus extends Component {
      @service siteSettings;

      get topic() {
        return this.args.outletArgs.topic;
      }

      get approved() {
        return this.topic.approved ?? this.topic.tz_approved;
      }

      get approvalIcon() {
        return safeIcon(
          this.topic.approval_icon || this.siteSettings.tz_approval_icon
        );
      }

      get approvedText() {
        return (
          this.topic.approval_approved_text || i18n("tz_approval.approved")
        );
      }

      <template>
        {{#if this.approved}}
          <span
            class="tz-approval-topic-status --tz-approved"
            data-tz-approval-topic-status
            title={{this.approvedText}}
            aria-label={{this.approvedText}}
          >
            {{dIcon this.approvalIcon}}
          </span>
        {{/if}}
      </template>
    }
  );

  api.registerValueTransformer("topic-list-item-class", ({ value, context }) => {
    if (context.topic.approved ?? context.topic.tz_approved) {
      value.push("status-tz-approved");

      if (context.topic.approval_profile_prefix) {
        value.push(`status-${context.topic.approval_profile_prefix}-approved`);
      }
    }

    return value;
  });
});
