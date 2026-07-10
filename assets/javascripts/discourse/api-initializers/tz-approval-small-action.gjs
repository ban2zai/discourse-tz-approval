import Component from "@glimmer/component";
import { htmlSafe, trustHTML } from "@ember/template";
import { modifier } from "ember-modifier";
import { apiInitializer } from "discourse/lib/api";
import { helperContext } from "discourse/lib/helpers";
import { autoUpdatingRelativeAge } from "discourse/lib/formatter";
import dIcon from "discourse-common/helpers/d-icon";
import { i18n } from "discourse-i18n";

const DEFAULT_ICON = "file-signature";
const ICON_REGEXP = /^[a-z0-9-]+$/;

function safeIcon(icon) {
  return ICON_REGEXP.test(icon || "") ? icon : DEFAULT_ICON;
}

function approvalProfiles() {
  const context = helperContext();
  const siteProfiles = context.site?.tz_approval_profiles;

  if (siteProfiles?.length) {
    return siteProfiles.map((profile) => ({
      key: profile.key,
      prefix: profile.prefix,
      icon: safeIcon(profile.icon || DEFAULT_ICON),
      approvedText: profile.approved_text,
      unapprovedText: profile.unapproved_text,
      approvedDescription: profile.approved_description,
      unapprovedDescription: profile.unapproved_description,
    }));
  }

  return [
    {
      key: "tz",
      prefix: "tz",
      icon: safeIcon(context.siteSettings.tz_approval_icon),
      approvedText: i18n("action_codes.tz_approved"),
      unapprovedText: i18n("action_codes.tz_unapproved"),
      approvedDescription: i18n("tz_approval.profiles.tz.approved_description"),
      unapprovedDescription: i18n("tz_approval.profiles.tz.unapproved_description"),
    },
  ];
}

function profileForActionCode(code) {
  return approvalProfiles().find((profile) => {
    return (
      code === `${profile.prefix}_approved` ||
      code === `${profile.prefix}_unapproved` ||
      code === `${profile.prefix}_author_locked` ||
      code === `${profile.prefix}_author_unlocked`
    );
  });
}

function isApprovedAction(code) {
  return code?.endsWith("_approved");
}

function isAuthorLockAction(code) {
  return code?.endsWith("_author_locked");
}

function isAuthorUnlockAction(code) {
  return code?.endsWith("_author_unlocked");
}

function isTzApprovalAction(code) {
  return !!profileForActionCode(code);
}

function approvalIcon(prefix) {
  return profileForActionCode(`${prefix}_approved`)?.icon || safeIcon(helperContext().siteSettings.tz_approval_icon);
}

export default apiInitializer((api) => {
  api.replaceIcon("notification.tz_approval", safeIcon(helperContext().siteSettings.tz_approval_icon));

  if (api.registerNotificationTypeRenderer) {
    api.registerNotificationTypeRenderer("tz_approval", (NotificationItemBase) => {
      return class extends NotificationItemBase {
        get linkTitle() {
          return i18n("tz_approval.notification.title");
        }

        get icon() {
          if (this.notification.data.action === "author_locked") {
            return "lock";
          }

          if (this.notification.data.action === "author_unlocked") {
            return "lock-open";
          }

          const prefix = this.notification.data.profile_prefix;
          return approvalIcon(prefix);
        }

        get description() {
          if (this.notification.data.description) {
            return this.notification.data.description;
          }

          const action = this.notification.data.action;
          const profile = approvalProfiles().find(
            (item) => item.key === this.notification.data.profile_key
          );

          if (profile) {
            return action === "unapproved"
              ? profile.unapprovedDescription
              : profile.approvedDescription;
          }

          return action === "unapproved"
            ? i18n("tz_approval.small_action.unapproved")
            : i18n("tz_approval.small_action.approved");
        }
      };
    });
  }

  api.registerValueTransformer("post-small-action-custom-component", ({ value, context }) => {
    if (!isTzApprovalAction(context.code)) {
      return value;
    }

    return class TzApprovalSmallAction extends Component {
      get title() {
        if (isAuthorLockAction(this.args.code)) {
          return i18n("tz_approval.small_action.author_locked");
        }

        if (isAuthorUnlockAction(this.args.code)) {
          return i18n("tz_approval.small_action.author_unlocked");
        }

        const profile = profileForActionCode(this.args.code);

        if (!profile) {
          return isApprovedAction(this.args.code)
            ? i18n("tz_approval.small_action.approved")
            : i18n("tz_approval.small_action.unapproved");
        }

        return isApprovedAction(this.args.code) ? profile.approvedText : profile.unapprovedText;
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
        if (isAuthorLockAction(this.args.code)) {
          return "lock";
        }

        if (isAuthorUnlockAction(this.args.code)) {
          return "lock-open";
        }

        return profileForActionCode(this.args.code)?.icon || safeIcon(DEFAULT_ICON);
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

    if (isAuthorLockAction(context.code)) {
      return "lock";
    }

    if (isAuthorUnlockAction(context.code)) {
      return "lock-open";
    }

    return profileForActionCode(context.code)?.icon || safeIcon(DEFAULT_ICON);
  });
});
