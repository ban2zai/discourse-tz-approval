import { apiInitializer } from "discourse/lib/api";
import { helperContext } from "discourse/lib/helpers";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

const DEFAULT_ICON = "file-signature";
const ICON_REGEXP = /^[a-z0-9-]+$/;

const APPROVAL_FIELDS = [
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
      return approvalIcon();
    },
    priority: 250,
    dependentKeys: ["topic.tz_approved", "topic.can_approve_tz", "topic.can_unapprove_tz"],

    displayed() {
      return !!this.topic.can_approve_tz || !!this.topic.can_unapprove_tz;
    },

    translatedLabel() {
      return this.topic.tz_approved
        ? I18n.t("tz_approval.unapprove")
        : I18n.t("tz_approval.approve");
    },

    classNames() {
      return this.topic.tz_approved ? ["btn-success"] : [];
    },

    async action() {
      const topic = this.topic;
      const currentUser = api.getCurrentUser();
      const isApproved = topic.tz_approved;
      const endpoint = isApproved
        ? "/tz-approval/unapprove"
        : "/tz-approval/approve";

      const previousState = Object.fromEntries(
        APPROVAL_FIELDS.map((field) => [field, topic[field]])
      );

      syncApprovalState(topic, {
        tz_approved: !isApproved,
        can_approve_tz: isApproved,
        can_unapprove_tz: !isApproved,
        tz_approved_by_username: isApproved ? null : currentUser?.username,
        tz_approved_by_id: isApproved ? null : currentUser?.id,
        tz_approved_at: isApproved ? null : new Date().toISOString(),
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
