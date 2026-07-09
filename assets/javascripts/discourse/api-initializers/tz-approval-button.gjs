import { apiInitializer } from "discourse/lib/api";
import { helperContext } from "discourse/lib/helpers";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";

const DEFAULT_ICON = "file-signature";
const ICON_REGEXP = /^[a-z0-9-]+$/;

const APPROVAL_FIELDS = [
  "approval_profile_key",
  "approval_profile_prefix",
  "approval_label",
  "approval_icon",
  "approval_approve_text",
  "approval_unapprove_text",
  "approval_approved_text",
  "approval_approved_by_author_text",
  "approved",
  "approved_by_id",
  "approved_by_username",
  "approved_at",
  "can_approve",
  "can_unapprove",
  "tz_approved",
  "tz_approved_by_id",
  "tz_approved_by_username",
  "tz_approved_at",
  "can_approve_tz",
  "can_unapprove_tz",
];

function safeIcon(icon) {
  return ICON_REGEXP.test(icon || "") ? icon : DEFAULT_ICON;
}

function approvalIcon() {
  return safeIcon(helperContext().siteSettings.tz_approval_icon);
}

function topicApprovalIcon(topic) {
  return safeIcon(topic.approval_icon || approvalIcon());
}

function isApproved(topic) {
  return topic.approved ?? topic.tz_approved;
}

function setModelApprovalState(model, state) {
  if (!model) {
    return;
  }

  APPROVAL_FIELDS.forEach((field) => {
    if (Object.prototype.hasOwnProperty.call(state, field)) {
      if (typeof model.set === "function") {
        model.set(field, state[field]);
      } else {
        model[field] = state[field];
      }
    }
  });
}

function syncApprovalState(topic, state) {
  setModelApprovalState(topic, state);

  topic.postStream?.posts?.forEach((post) => {
    if (post.post_number === 1 && !post.topic) {
      if (typeof post.set === "function") {
        post.set("topic", topic);
      } else {
        post.topic = topic;
      }
    }

    setModelApprovalState(post.topic, state);
  });
}

export default apiInitializer((api) => {
  api.registerTopicFooterButton({
    id: "tz-approval",
    icon() {
      return topicApprovalIcon(this.topic);
    },
    priority: 250,
    dependentKeys: [
      "topic.approved",
      "topic.can_approve",
      "topic.can_unapprove",
      "topic.tz_approved",
      "topic.can_approve_tz",
      "topic.can_unapprove_tz",
    ],

    displayed() {
      return (
        !!this.topic.can_approve ||
        !!this.topic.can_unapprove ||
        !!this.topic.can_approve_tz ||
        !!this.topic.can_unapprove_tz
      );
    },

    translatedLabel() {
      return isApproved(this.topic)
        ? this.topic.approval_unapprove_text || i18n("tz_approval.unapprove")
        : this.topic.approval_approve_text || i18n("tz_approval.approve");
    },

    classNames() {
      return isApproved(this.topic)
        ? ["tz-approval-footer-button", "btn-success"]
        : ["tz-approval-footer-button"];
    },

    async action() {
      const topic = this.topic;
      const currentUser = api.getCurrentUser();
      const currentlyApproved = isApproved(topic);
      const isTzProfile = topic.approval_profile_key === "tz" || !topic.approval_profile_key;
      const endpoint = currentlyApproved
        ? "/tz-approval/unapprove"
        : "/tz-approval/approve";

      const previousState = Object.fromEntries(
        APPROVAL_FIELDS.map((field) => [field, topic[field]])
      );

      syncApprovalState(topic, {
        approved: !currentlyApproved,
        can_approve: currentlyApproved,
        can_unapprove: !currentlyApproved,
        approved_by_username: currentlyApproved ? null : currentUser?.username,
        approved_by_id: currentlyApproved ? null : currentUser?.id,
        approved_at: currentlyApproved ? null : new Date().toISOString(),
        tz_approved: isTzProfile ? !currentlyApproved : topic.tz_approved,
        can_approve_tz: isTzProfile ? currentlyApproved : topic.can_approve_tz,
        can_unapprove_tz: isTzProfile ? !currentlyApproved : topic.can_unapprove_tz,
        tz_approved_by_username: isTzProfile
          ? currentlyApproved
            ? null
            : currentUser?.username
          : topic.tz_approved_by_username,
        tz_approved_by_id: isTzProfile
          ? currentlyApproved
            ? null
            : currentUser?.id
          : topic.tz_approved_by_id,
        tz_approved_at: isTzProfile
          ? currentlyApproved
            ? null
            : new Date().toISOString()
          : topic.tz_approved_at,
      });

      try {
        const result = await ajax(endpoint, { type: "POST", data: { topic_id: topic.id } });
        syncApprovalState(topic, result);
      } catch (e) {
        syncApprovalState(topic, previousState);
        popupAjaxError(e);
      }
    },
  });
});
