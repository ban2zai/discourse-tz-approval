import { apiInitializer } from "discourse/lib/api";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

export default apiInitializer((api) => {
  api.registerTopicFooterButton({
    id: "tz-approval",
    icon: "stamp",
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

      const prevUsername = topic.tz_approved_by_username;
      const prevById = topic.tz_approved_by_id;

      topic.set("tz_approved", !isApproved);
      topic.set("can_approve_tz", isApproved);
      topic.set("can_unapprove_tz", !isApproved);
      topic.set("tz_approved_by_username", isApproved ? null : currentUser?.username);
      topic.set("tz_approved_by_id", isApproved ? null : currentUser?.id);

      try {
        await ajax(endpoint, { type: "POST", data: { topic_id: topic.id } });
      } catch (e) {
        topic.set("tz_approved", isApproved);
        topic.set("can_approve_tz", !isApproved);
        topic.set("can_unapprove_tz", isApproved);
        topic.set("tz_approved_by_username", prevUsername);
        topic.set("tz_approved_by_id", prevById);
        popupAjaxError(e);
      }
    },
  });

});
