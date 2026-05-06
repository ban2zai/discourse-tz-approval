import Component from "@glimmer/component";
import { htmlSafe } from "@ember/template";
import { inject as service } from "@ember/service";
import { apiInitializer } from "discourse/lib/api";
import dIcon from "discourse-common/helpers/d-icon";
import { eq } from "truth-helpers";
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
  api.renderAfterWrapperOutlet(
    "post-content-cooked-html",
    class TzApprovalPostStatus extends Component {
      @service siteSettings;

      static shouldRender(args) {
        return args.post?.post_number === 1;
      }

      get post() {
        return this.args.post;
      }

      get topic() {
        return this.post?.topic;
      }

      get approvalIcon() {
        return safeIcon(this.siteSettings.tz_approval_icon);
      }

      get approvalColor() {
        const lightColor = safeColor(this.siteSettings.tz_approval_light_color, "#d9a441");
        const darkColor = safeColor(this.siteSettings.tz_approval_dark_color, "#d9a441");

        return `light-dark(${lightColor}, ${darkColor})`;
      }

      get badgeStyle() {
        const color = this.approvalColor;

        return htmlSafe(`
          display: flex;
          align-items: center;
          gap: 10px;
          background: color-mix(in srgb, ${color} 12%, transparent);
          color: var(--primary);
          border: 1px solid color-mix(in srgb, ${color} 45%, transparent);
          border-left: 4px solid ${color};
          border-radius: 6px;
          padding: 10px 12px;
          margin-top: 14px;
          font-size: 0.95em;
          line-height: 1.35;
        `);
      }

      get iconStyle() {
        const color = this.approvalColor;

        return htmlSafe(`
          display: inline-flex;
          align-items: center;
          justify-content: center;
          width: 28px;
          height: 28px;
          flex: 0 0 28px;
          border-radius: 4px;
          background: color-mix(in srgb, ${color} 18%, transparent);
          color: ${color};
        `);
      }

      <template>
        {{#if this.topic.tz_approved}}
          <div style={{this.badgeStyle}}>
            <span style={{this.iconStyle}}>
              {{dIcon this.approvalIcon}}
            </span>

            <span style="min-width: 0; font-weight: 600;">
              {{#if (eq this.topic.tz_approved_by_id this.post.user_id)}}
                {{i18n "tz_approval.approved_by_author"}}
              {{else if this.topic.tz_approved_by_username}}
                {{i18n "tz_approval.approved_by" username=this.topic.tz_approved_by_username}}
              {{else}}
                {{i18n "tz_approval.approved_by_author"}}
              {{/if}}
            </span>
          </div>
        {{/if}}
      </template>
    }
  );
});
