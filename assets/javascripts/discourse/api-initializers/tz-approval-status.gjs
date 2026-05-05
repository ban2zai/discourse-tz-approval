import Component from "@glimmer/component";
import { apiInitializer } from "discourse/lib/api";
import dIcon from "discourse-common/helpers/d-icon";
import { eq } from "truth-helpers";
import { i18n } from "discourse-i18n";

export default apiInitializer((api) => {
  api.renderAfterWrapperOutlet(
    "post-content-cooked-html",
    class TzApprovalPostStatus extends Component {
      static shouldRender(args) {
        return args.post?.post_number === 1 && args.post?.topic?.tz_approved;
      }

      <template>
        <div
          style="
            display: flex;
            align-items: center;
            gap: 10px;
            background: color-mix(in srgb, var(--success-low) 88%, transparent);
            color: var(--primary);
            border: 1px solid color-mix(in srgb, var(--success) 45%, transparent);
            border-left: 4px solid var(--success);
            border-radius: 6px;
            padding: 10px 12px;
            margin-top: 14px;
            font-size: 0.95em;
            line-height: 1.35;
          "
        >
          <span
            style="
              display: inline-flex;
              align-items: center;
              justify-content: center;
              width: 28px;
              height: 28px;
              flex: 0 0 28px;
              border-radius: 4px;
              background: var(--success);
              color: var(--secondary);
            "
          >
            {{dIcon "stamp"}}
          </span>

          <span style="min-width: 0; font-weight: 600;">
            {{#if (eq @post.topic.tz_approved_by_id @post.user_id)}}
              {{i18n "tz_approval.approved_by_author"}}
            {{else if @post.topic.tz_approved_by_username}}
              {{i18n "tz_approval.approved_by" username=@post.topic.tz_approved_by_username}}
            {{else}}
              {{i18n "tz_approval.approved_by_author"}}
            {{/if}}
          </span>
        </div>
      </template>
    }
  );
});
