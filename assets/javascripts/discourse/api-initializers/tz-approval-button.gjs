import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { apiInitializer } from "discourse/lib/api";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { helperContext } from "discourse/lib/helpers";
import DButton from "discourse/ui-kit/d-button";
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
  "approved_by_author",
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
  "author_approval_locked",
  "author_approval_locked_by_id",
  "author_approval_locked_by_username",
  "author_approval_locked_at",
  "can_lock_author_approval",
  "can_unlock_author_approval",
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

function approvalStateSnapshot(topic) {
  return Object.fromEntries(
    APPROVAL_FIELDS.map((field) => [field, topic?.[field]])
  );
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

class TzApprovalFooterActions extends Component {
  @service currentUser;
  @tracked pendingApprovalState = null;

  get topic() {
    return this.args.outletArgs.topic;
  }

  get approvalState() {
    return this.pendingApprovalState?.topicId === this.topic?.id
      ? this.pendingApprovalState.values
      : this.topic;
  }

  get actionPending() {
    return this.pendingApprovalState?.topicId === this.topic?.id;
  }

  setPendingApprovalState(topic, state) {
    const requestId = Symbol();

    this.pendingApprovalState = {
      topicId: topic.id,
      requestId,
      values: {
        ...approvalStateSnapshot(this.approvalState),
        ...state,
      },
    };
    syncApprovalState(topic, state);

    return requestId;
  }

  settleApprovalState(topic, state, requestId) {
    syncApprovalState(topic, state);

    if (this.topic?.id === topic.id && this.topic !== topic) {
      syncApprovalState(this.topic, state);
    }

    if (this.pendingApprovalState?.requestId === requestId) {
      this.pendingApprovalState = null;
    }
  }

  get displayed() {
    return this.canChangeApproval || this.canChangeAuthorLock;
  }

  get footerActionsLabel() {
    return i18n("tz_approval.footer_actions");
  }

  get canChangeApproval() {
    const state = this.approvalState;

    return (
      !!state.can_approve ||
      !!state.can_unapprove ||
      !!state.can_approve_tz ||
      !!state.can_unapprove_tz
    );
  }

  get canChangeAuthorLock() {
    const state = this.approvalState;

    return (
      !!state.can_lock_author_approval ||
      !!state.can_unlock_author_approval
    );
  }

  get approvalIcon() {
    return topicApprovalIcon(this.approvalState);
  }

  get approvalLabel() {
    const state = this.approvalState;

    return isApproved(state)
      ? state.approval_unapprove_text || i18n("tz_approval.unapprove")
      : state.approval_approve_text || i18n("tz_approval.approve");
  }

  get approvalButtonClass() {
    const classes = [
      "btn-default",
      "topic-footer-button",
      "tz-approval-footer-action",
      "tz-approval-footer-button",
    ];

    if (isApproved(this.approvalState)) {
      classes.push("btn-success");
    }

    return classes.join(" ");
  }

  get authorLockIcon() {
    return this.approvalState.author_approval_locked ? "lock-open" : "lock";
  }

  get authorLockLabel() {
    return this.approvalState.author_approval_locked
      ? i18n("tz_approval.unlock_author_approval")
      : i18n("tz_approval.lock_author_approval");
  }

  get authorLockButtonClass() {
    const classes = [
      "btn-default",
      "topic-footer-button",
      "tz-approval-footer-action",
      "tz-approval-author-lock-button",
    ];

    if (this.approvalState.author_approval_locked) {
      classes.push("btn-danger");
    }

    return classes.join(" ");
  }

  @action
  async changeApproval() {
    if (this.actionPending) {
      return;
    }

    const topic = this.topic;
    const state = this.approvalState;
    const currentlyApproved = isApproved(state);
    const isTzProfile =
      state.approval_profile_key === "tz" || !state.approval_profile_key;
    const approvedByAuthor =
      !currentlyApproved && this.currentUser?.id === topic.user_id;
    const endpoint = currentlyApproved
      ? "/tz-approval/unapprove"
      : "/tz-approval/approve";
    const previousState = approvalStateSnapshot(state);

    const requestId = this.setPendingApprovalState(topic, {
      approved: !currentlyApproved,
      approved_by_author: approvedByAuthor,
      can_approve: currentlyApproved,
      can_unapprove: !currentlyApproved,
      approved_by_username:
        currentlyApproved || approvedByAuthor ? null : this.currentUser?.username,
      approved_by_id:
        currentlyApproved || approvedByAuthor ? null : this.currentUser?.id,
      approved_at: currentlyApproved ? null : new Date().toISOString(),
      tz_approved: isTzProfile ? !currentlyApproved : state.tz_approved,
      can_approve_tz: isTzProfile ? currentlyApproved : state.can_approve_tz,
      can_unapprove_tz: isTzProfile
        ? !currentlyApproved
        : state.can_unapprove_tz,
      tz_approved_by_username: isTzProfile
        ? currentlyApproved || approvedByAuthor
          ? null
          : this.currentUser?.username
        : state.tz_approved_by_username,
      tz_approved_by_id: isTzProfile
        ? currentlyApproved || approvedByAuthor
          ? null
          : this.currentUser?.id
        : state.tz_approved_by_id,
      tz_approved_at: isTzProfile
        ? currentlyApproved
          ? null
          : new Date().toISOString()
        : state.tz_approved_at,
    });

    try {
      const result = await ajax(endpoint, {
        type: "POST",
        data: { topic_id: topic.id },
      });
      this.settleApprovalState(topic, result, requestId);
    } catch (error) {
      this.settleApprovalState(topic, previousState, requestId);
      popupAjaxError(error);
    }
  }

  @action
  async changeAuthorLock() {
    if (this.actionPending) {
      return;
    }

    const topic = this.topic;
    const state = this.approvalState;
    const currentlyLocked = !!state.author_approval_locked;
    const endpoint = currentlyLocked
      ? "/tz-approval/unlock-author-approval"
      : "/tz-approval/lock-author-approval";
    const previousState = approvalStateSnapshot(state);

    const requestId = this.setPendingApprovalState(topic, {
      author_approval_locked: !currentlyLocked,
      author_approval_locked_by_id: currentlyLocked ? null : this.currentUser?.id,
      author_approval_locked_by_username: currentlyLocked
        ? null
        : this.currentUser?.username,
      author_approval_locked_at: currentlyLocked
        ? null
        : new Date().toISOString(),
      can_lock_author_approval: currentlyLocked,
      can_unlock_author_approval: !currentlyLocked,
    });

    try {
      const result = await ajax(endpoint, {
        type: "POST",
        data: { topic_id: topic.id },
      });
      this.settleApprovalState(topic, result, requestId);
    } catch (error) {
      this.settleApprovalState(topic, previousState, requestId);
      popupAjaxError(error);
    }
  }

  <template>
    {{#if this.displayed}}
      <section
        class="tz-approval-footer-actions-row"
        role="group"
        aria-label={{this.footerActionsLabel}}
      >
        {{#if this.canChangeApproval}}
          <DButton
            @action={{this.changeApproval}}
            @icon={{this.approvalIcon}}
            @translatedLabel={{this.approvalLabel}}
            @translatedAriaLabel={{this.approvalLabel}}
            @disabled={{this.actionPending}}
            id="topic-footer-button-tz-approval"
            class={{this.approvalButtonClass}}
          />
        {{/if}}

        {{#if this.canChangeAuthorLock}}
          <DButton
            @action={{this.changeAuthorLock}}
            @icon={{this.authorLockIcon}}
            @translatedLabel={{this.authorLockLabel}}
            @translatedAriaLabel={{this.authorLockLabel}}
            @disabled={{this.actionPending}}
            id="topic-footer-button-tz-approval-author-lock"
            class={{this.authorLockButtonClass}}
          />
        {{/if}}
      </section>
    {{/if}}
  </template>
}

export default apiInitializer((api) => {
  api.renderInOutlet("after-topic-footer-buttons", TzApprovalFooterActions);
});
