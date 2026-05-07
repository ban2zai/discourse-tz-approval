import Component from "@glimmer/component";
import { service } from "@ember/service";
import { apiInitializer } from "discourse/lib/api";
import UserLink from "discourse/components/user-link";
import dIcon from "discourse-common/helpers/d-icon";
import { eq } from "truth-helpers";
import { i18n } from "discourse-i18n";

const DEFAULT_ICON = "file-signature";
const ICON_REGEXP = /^[a-z0-9-]+$/;

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

      <template>
        {{#if this.topic.tz_approved}}
          <div
            class="tz-approval-post-badge"
            data-tz-approval-post-badge
          >
            <span class="tz-approval-post-badge__icon">
              {{dIcon this.approvalIcon}}
            </span>

            <span class="tz-approval-post-badge__text">
              {{#if (eq this.topic.tz_approved_by_id this.post.user_id)}}
                {{i18n "tz_approval.approved_by_author"}}
              {{else if this.topic.tz_approved_by_username}}
                {{i18n "tz_approval.approved"}}
                —
                <UserLink
                  @username={{this.topic.tz_approved_by_username}}
                  class="tz-approval-post-badge__user"
                >
                  @{{this.topic.tz_approved_by_username}}
                </UserLink>
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
