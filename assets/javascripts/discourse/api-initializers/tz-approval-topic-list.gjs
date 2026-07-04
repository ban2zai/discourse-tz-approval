import Component from "@glimmer/component";
import { service } from "@ember/service";
import { modifier } from "ember-modifier";
import { apiInitializer } from "discourse/lib/api";
import dIcon from "discourse-common/helpers/d-icon";
import { i18n } from "discourse-i18n";

const DEFAULT_ICON = "file-signature";
const ICON_REGEXP = /^[a-z0-9-]+$/;

function safeIcon(icon) {
  return ICON_REGEXP.test(icon || "") ? icon : DEFAULT_ICON;
}

function removeClone(clone) {
  if (clone?.parentNode) {
    clone.parentNode.removeChild(clone);
  }
}

function syncClone(source, clone) {
  clone.className = source.className;
  clone.title = source.title;
  clone.removeAttribute("hidden");
  clone.removeAttribute("aria-hidden");
  clone.style.removeProperty("display");

  if (clone.innerHTML !== source.innerHTML) {
    clone.innerHTML = source.innerHTML;
  }

  const ariaLabel = source.getAttribute("aria-label");

  if (ariaLabel) {
    clone.setAttribute("aria-label", ariaLabel);
  } else {
    clone.removeAttribute("aria-label");
  }
}

export default apiInitializer((api) => {
  api.renderInOutlet(
    "topic-list-before-status",
    class TzApprovalTopicListIcon extends Component {
      @service siteSettings;

      get approvalIcon() {
        return safeIcon(
          this.args.outletArgs.topic.approval_icon || this.siteSettings.tz_approval_icon
        );
      }

      get approved() {
        const topic = this.args.outletArgs.topic;
        return topic.approved ?? topic.tz_approved;
      }

      get approvedText() {
        return this.args.outletArgs.topic.approval_approved_text || i18n("tz_approval.approved");
      }

      moveIntoTopicStatuses = modifier((element) => {
        let clone = null;
        let frame = null;

        element.style.display = "none";
        element.setAttribute("aria-hidden", "true");

        const move = () => {
          const statuses = element.closest(".link-top-line")?.querySelector(".topic-statuses");

          if (!statuses) {
            return;
          }

          if (!clone) {
            clone = element.cloneNode(true);
            clone.dataset.tzApprovalTopicStatusClone = "";
          }

          syncClone(element, clone);

          if (clone.parentElement !== statuses) {
            const existingClone = statuses.querySelector(
              "[data-tz-approval-topic-status-clone]"
            );

            if (existingClone && existingClone !== clone) {
              removeClone(existingClone);
            }

            statuses.appendChild(clone);
          }
        };

        const scheduleMove = () => {
          cancelAnimationFrame(frame);
          frame = requestAnimationFrame(move);
        };

        move();
        scheduleMove();

        const observerTarget = element.closest(".link-top-line") || document.body;
        const observer = new MutationObserver(scheduleMove);
        observer.observe(observerTarget, { childList: true, subtree: true });

        return () => {
          cancelAnimationFrame(frame);
          observer.disconnect();
          removeClone(clone);
        };
      });

      <template>
        {{#if this.approved}}
          <span
            class="tz-approval-topic-status --tz-approved"
            data-tz-approval-topic-status
            title={{this.approvedText}}
            aria-label={{this.approvedText}}
            hidden
            {{this.moveIntoTopicStatuses}}
          >
            {{dIcon this.approvalIcon}}
          </span>
        {{/if}}
      </template>
    }
  );

  api.registerValueTransformer("topic-list-item-class", ({ value, context }) => {
    if (context.topic.approved ?? context.topic.tz_approved) {
      value.push("status-tz-approved");

      if (context.topic.approval_profile_prefix) {
        value.push(`status-${context.topic.approval_profile_prefix}-approved`);
      }
    }

    return value;
  });
});
