import Component from "@glimmer/component";
import { htmlSafe, trustHTML } from "@ember/template";
import { modifier } from "ember-modifier";
import { apiInitializer } from "discourse/lib/api";
import { helperContext } from "discourse/lib/helpers";
import { autoUpdatingRelativeAge } from "discourse/lib/formatter";
import dIcon from "discourse-common/helpers/d-icon";
import { i18n } from "discourse-i18n";

const TZ_APPROVAL_ACTION_CODES = ["tz_approved", "tz_unapproved"];
const DEFAULT_ICON = "file-signature";
const ICON_REGEXP = /^[a-z0-9-]+$/;

function isTzApprovalAction(code) {
  return TZ_APPROVAL_ACTION_CODES.includes(code);
}

function safeIcon(icon) {
  return ICON_REGEXP.test(icon || "") ? icon : DEFAULT_ICON;
}

function approvalIcon() {
  return safeIcon(helperContext().siteSettings.tz_approval_icon);
}

export default apiInitializer((api) => {
  api.registerValueTransformer("post-small-action-custom-component", ({ value, context }) => {
    if (!isTzApprovalAction(context.code)) {
      return value;
    }

    return class TzApprovalSmallAction extends Component {
      get title() {
        return i18n(`action_codes.${this.args.code}`);
      }

      get cooked() {
        return trustHTML(this.args.post.cooked || "");
      }

      get relativeTime() {
        return htmlSafe(
          autoUpdatingRelativeAge(this.args.createdAt, {
            format: "medium",
            title: true,
          })
        );
      }

      installLayout = modifier((element) => {
        const article = element.closest("article.small-action");
        let frame = null;

        const applyLayout = () => {
          article?.classList.add("tz-approval-small-action-layout");
        };

        const scheduleApplyLayout = () => {
          cancelAnimationFrame(frame);
          frame = requestAnimationFrame(applyLayout);
        };

        applyLayout();
        scheduleApplyLayout();

        const observer = new MutationObserver(scheduleApplyLayout);

        if (article) {
          observer.observe(article, { childList: true, subtree: true });
        }

        return () => {
          cancelAnimationFrame(frame);
          observer.disconnect();
          article?.classList.remove("tz-approval-small-action-layout");
        };
      });

      get approvalIcon() {
        return approvalIcon();
      }

      <template>
        <div
          class="tz-approval-small-action"
          data-tz-approval-small-action
          data-tz-approval-action-code={{@code}}
          {{this.installLayout}}
        >
          <span
            class="tz-approval-small-action__icon"
            data-tz-approval-small-action-icon
          >
            {{dIcon this.approvalIcon}}
          </span>

          <div class="tz-approval-small-action__title">
            {{this.title}}
          </div>

          <div
            class="tz-approval-small-action__time"
            data-tz-approval-small-action-time
          >
            {{this.relativeTime}}
          </div>

          {{#if @post.cooked}}
            <div class="tz-approval-small-action__message">
              {{this.cooked}}
            </div>
          {{/if}}
        </div>
      </template>
    };
  });

  api.registerValueTransformer("post-small-action-class", ({ value, context }) => {
    const code = context.post?.action_code || context.post?.actionCode || context.code;

    if (isTzApprovalAction(code)) {
      value.push("tz-approval-small-action-post");
    }

    return value;
  });

  api.registerValueTransformer("post-small-action-icon", ({ value, context }) => {
    if (!isTzApprovalAction(context.code)) {
      return value;
    }

    return approvalIcon();
  });
});
