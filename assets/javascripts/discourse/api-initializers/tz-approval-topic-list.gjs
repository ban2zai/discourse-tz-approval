import Component from "@glimmer/component";
import { htmlSafe } from "@ember/template";
import { service } from "@ember/service";
import { modifier } from "ember-modifier";
import { apiInitializer } from "discourse/lib/api";
import dIcon from "discourse-common/helpers/d-icon";
import { i18n } from "discourse-i18n";

const DEFAULT_ICON = "file-signature";
const ICON_REGEXP = /^[a-z0-9-]+$/;

function safeColor(color, fallback) {
  return /^#[0-9a-fA-F]{3,8}$/.test(color || "") ? color : fallback;
}

function safeIcon(icon) {
  return ICON_REGEXP.test(icon || "") ? icon : DEFAULT_ICON;
}

export default apiInitializer((api) => {
  api.renderInOutlet(
    "topic-list-before-status",
    class TzApprovalTopicListIcon extends Component {
      @service siteSettings;

      get approvalColor() {
        const lightColor = safeColor(this.siteSettings.tz_approval_light_color, "#d9a441");
        const darkColor = safeColor(this.siteSettings.tz_approval_dark_color, "#d9a441");

        return `light-dark(${lightColor}, ${darkColor})`;
      }

      get approvalIcon() {
        return safeIcon(this.siteSettings.tz_approval_icon);
      }

      get iconStyle() {
        const color = this.approvalColor;

        return htmlSafe(`
          display: inline-flex;
          align-items: center;
          justify-content: center;
          width: 17px;
          height: 17px;
          flex: 0 0 17px;
          border-radius: 4px;
          background: color-mix(in srgb, ${color} 14%, transparent);
          color: ${color};
        `);
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
            style={{this.iconStyle}}
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
