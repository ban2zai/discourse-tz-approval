import Component from "@glimmer/component";
import { htmlSafe } from "@ember/template";
import { inject as service } from "@ember/service";
import { apiInitializer } from "discourse/lib/api";
import dIcon from "discourse-common/helpers/d-icon";

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
          margin-right: 5px;
        `);
      }

      <template>
        {{#if @outletArgs.topic.tz_approved}}
          <span title="ТЗ одобрено" style={{this.iconStyle}}>
            {{dIcon this.approvalIcon}}
          </span>
        {{/if}}
      </template>
    }
  );
});
