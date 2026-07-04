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
        return safeIcon(this.topic?.approval_icon || this.siteSettings.tz_approval_icon);
      }

      get approved() {
        return this.topic?.approved ?? this.topic?.tz_approved;
      }

      get approvedById() {
        return this.topic?.approved_by_id ?? this.topic?.tz_approved_by_id;
      }

      get approvedByUsername() {
        return this.topic?.approved_by_username ?? this.topic?.tz_approved_by_username;
      }

      get approvedText() {
        return this.topic?.approval_approved_text || i18n("tz_approval.approved");
      }

      get approvedByAuthorText() {
        return this.topic?.approval_approved_by_author_text || i18n("tz_approval.approved_by_author");
      }

      <template>
        {{#if this.approved}}
          <div
            class="tz-approval-post-badge"
            data-tz-approval-post-badge
          >
            <span class="tz-approval-post-badge__icon">
              {{dIcon this.approvalIcon}}
            </span>

            <span class="tz-approval-post-badge__text">
              {{#if (eq this.approvedById this.post.user_id)}}
                {{this.approvedByAuthorText}}
              {{else if this.approvedByUsername}}
                {{this.approvedText}}
                —
                <UserLink
                  @username={{this.approvedByUsername}}
                  class="tz-approval-post-badge__user"
                >
                  @{{this.approvedByUsername}}
                </UserLink>
              {{else}}
                {{this.approvedByAuthorText}}
              {{/if}}
            </span>
          </div>
        {{/if}}
      </template>
    }
  );
});
