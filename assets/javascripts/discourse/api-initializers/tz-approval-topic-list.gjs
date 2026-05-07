import Component from "@glimmer/component";
import { service } from "@ember/service";
import { modifier } from "ember-modifier";
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
    "topic-list-before-status",
    class TzApprovalTopicListIcon extends Component {
      @service siteSettings;

      get approvalIcon() {
        return safeIcon(this.siteSettings.tz_approval_icon);
      }

      moveIntoTopicStatuses = modifier((element) => {
        const move = () => {
          const statuses = element.closest(".link-top-line")?.querySelector(".topic-statuses");

          if (statuses && element.parentElement !== statuses) {
            statuses.appendChild(element);
          }
        };

        move();
        const frame = requestAnimationFrame(move);

        return () => {
          cancelAnimationFrame(frame);
          element.remove();
        };
      });

      <template>
        {{#if @outletArgs.topic.tz_approved}}
          <span
            class="tz-approval-topic-status topic-status --tz-approved"
            data-tz-approval-topic-status
            title={{i18n "tz_approval.approved"}}
            aria-label={{i18n "tz_approval.approved"}}
            {{this.moveIntoTopicStatuses}}
          >
            {{dIcon this.approvalIcon}}
          </span>
        {{/if}}
      </template>
    }
  );

  api.registerValueTransformer("topic-list-item-class", ({ value, context }) => {
    if (context.topic.tz_approved) {
      value.push("status-tz-approved");
    }

    return value;
  });
});
